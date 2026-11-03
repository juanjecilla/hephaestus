#!/bin/bash
# Tests for the merge-queue scripts, against a fake `gh` (test/fake-gh) and JSON fixtures.
#   extras/test/queue-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; X="$(dirname "$HERE")"
pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
expect()      { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected '$3', got '$2'"; fi; }
expect_has()  { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1: '$3' not in: $2"; fi; }
expect_file() { if [ -e "$2" ]; then ok "$1"; else bad "$1: no $2"; fi; }
expect_none() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1: $2 exists"; fi; }

SINCE="2026-11-01T09:00:00Z"
TMPS=()
trap 'rm -rf "${TMPS[@]}"' EXIT
setup() {
  FAKE_DIR="$(mktemp -d)"; export FAKE_DIR; TMPS+=("$FAKE_DIR")
  mkdir "$FAKE_DIR/bin"; ln -s "$HERE/fake-gh" "$FAKE_DIR/bin/gh"
  export PATH="$FAKE_DIR/bin:$PATH" POLL=0 RESOLVE_WAIT=0 REVIEW_WAIT=2 CHECKS_TIMEOUT=60 RETARGET_WAIT=0 MARGIN=0 RATE_MARGIN=0 STAMP="$FAKE_DIR/stamp"
  echo '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}' >"$FAKE_DIR/repo.json"
}
# pr N STATE [DECISION] [BASE] [COMMENT_BODY]
pr() {
  local comments='[]'; [ -n "${5:-}" ] && comments="[{\"author\":{\"login\":\"coderabbitai\"},\"createdAt\":\"2026-11-01T10:00:00Z\",\"body\":\"$5\"}]"
  local reviews='[]'; [ "$2" != none ] && reviews="[{\"author\":{\"login\":\"coderabbitai\"},\"submittedAt\":\"2026-11-01T10:00:00Z\",\"state\":\"$2\",\"commit\":{\"oid\":\"abc\"}}]"
  cat >"$FAKE_DIR/pr-$1.json" <<J
{"reviews":$reviews,"comments":$comments,"reviewDecision":"${3:-$2}","headRefOid":"abc","baseRefName":"${4:-develop}"}
J
}
checks() { echo "$2" >"$FAKE_DIR/checks-$1${3:+.$3}.json"; }
REQ_PASS='[{"name":"build","bucket":"pass","required":true}]'
DEPENDABOT_QUEUED='{"name":".github/dependabot.yml","bucket":"pending","required":false}'

echo "fullreview.sh"
setup; pr 1 APPROVED; checks 1 "[{\"name\":\"build\",\"bucket\":\"pass\",\"required\":true},$DEPENDABOT_QUEUED]"
out="$(cd / && "$X/fullreview.sh" 1 "$SINCE")"
expect_has "an approved PR merges although a check nothing requires never leaves the queue (#648)" "$out" "merged 1"
expect_file "and the merge was asked for" "$FAKE_DIR/merged-1"
expect_has "it asks gh for the required checks only" "$(cat "$FAKE_DIR/log")" "pr checks 1 --required"
expect_none "and never watches the queued one" "$FAKE_DIR/stalled"

setup; pr 2 APPROVED; checks 2 '[{"name":"build","bucket":"fail","required":true}]'
out="$("$X/fullreview.sh" 2 "$SINCE")"
expect "a failing required check stops the queue" "$out" "review 2: APPROVED
STOP 2: CI failing"
expect_none "and nothing merges" "$FAKE_DIR/merged-2"

setup; pr 3 APPROVED; checks 3 '[{"name":"build","bucket":"pending","required":true}]'
out="$(CHECKS_TIMEOUT=0 "$X/fullreview.sh" 3 "$SINCE")"
expect_has "a required check that never finishes stops with a reason instead of hanging" "$out" "STOP 3: required checks still pending"
expect_none "and nothing merges" "$FAKE_DIR/merged-3"

setup; pr 4 APPROVED; checks 4 '[{"name":"build","bucket":"pending","required":true}]' 1; checks 4 "$REQ_PASS" 2
out="$("$X/fullreview.sh" 4 "$SINCE")"
expect_has "a required check that finishes while waiting is waited for" "$out" "merged 4"

setup; pr 5 CHANGES_REQUESTED; checks 5 "$REQ_PASS"
out="$("$X/fullreview.sh" 5 "$SINCE")"
expect_has "changes requested stops" "$out" "STOP 5: review state=CHANGES_REQUESTED"
expect_none "and nothing merges" "$FAKE_DIR/merged-5"

setup; pr 6 none APPROVED develop "Review limit reached"; checks 6 "$REQ_PASS"
# The head was approved before the limit reply: the review list carries that approval, older than SINCE.
jq '.reviews = [{"author":{"login":"coderabbitai"},"submittedAt":"2026-11-01T08:00:00Z","state":"APPROVED","commit":{"oid":"abc"}}]' "$FAKE_DIR/pr-6.json" >"$FAKE_DIR/t" && mv "$FAKE_DIR/t" "$FAKE_DIR/pr-6.json"
out="$("$X/fullreview.sh" 6 "$SINCE")"
expect_has "a rate-limit reply after the head was approved still merges (#512)" "$out" "merged 6"

setup; pr 7 none CHANGES_REQUESTED develop "Review limit reached"; checks 7 "$REQ_PASS"
out="$("$X/fullreview.sh" 7 "$SINCE")"
expect "a rate limit with no approval of the head stops" "$out" "STOP 7: rate limited (full review)"

# limited N WAIT_TEXT: a rate-limit reply posted after the request (2099), no review yet
limited() { pr "$1" none CHANGES_REQUESTED develop "Review limit reached. Your next included review will be available in $2."
  jq '.comments[0].createdAt = "2099-01-01T00:00:00Z"' "$FAKE_DIR/pr-$1.json" >"$FAKE_DIR/t" && mv "$FAKE_DIR/t" "$FAKE_DIR/pr-$1.json"; }
approved_later() { echo "{\"reviews\":[{\"author\":{\"login\":\"coderabbitai\"},\"submittedAt\":\"2099-01-01T00:00:00Z\",\"state\":\"APPROVED\",\"commit\":{\"oid\":\"abc\"}}],\"comments\":[],\"reviewDecision\":\"APPROVED\",\"headRefOid\":\"abc\",\"baseRefName\":\"develop\"}" >"$FAKE_DIR/on-comment-$1.json"; }

setup; limited 40 "0 seconds"; approved_later 40; checks 40 "$REQ_PASS"
out="$(RATE_MARGIN=0 "$X/fullreview.sh" 40 "$SINCE")"
expect_has "a rate limit with seconds to go is sat out and asked again (#588)" "$out" "merged 40"
expect_has "with a new request" "$(cat "$FAKE_DIR/log")" "pr comment 40 --body @coderabbitai full review"
expect_has "which is recorded for the next window" "$(cat "$FAKE_DIR/stamp" 2>/dev/null)" "$(date +%s | cut -c1-6)"

setup; limited 41 "47 minutes"; checks 41 "$REQ_PASS"
out="$("$X/fullreview.sh" 41 "$SINCE")"
expect "a long stated wait still stops at once" "$out" "STOP 41: rate limited (full review)"
expect "without asking again" "$(grep -c 'pr comment 41' "$FAKE_DIR/log")" "0"

setup; limited 42 "1 minute and 5 seconds"; checks 42 "$REQ_PASS"
out="$(RATE_RETRY_MAX=64 "$X/fullreview.sh" 42 "$SINCE")"
expect "minutes and seconds both count towards the stated wait (65 s is over a 64 s limit)" "$out" "STOP 42: rate limited (full review)"
expect "so it does not ask again" "$(grep -c 'pr comment 42' "$FAKE_DIR/log")" "0"

setup; pr 8 none; checks 8 "$REQ_PASS"
out="$(REVIEW_WAIT=1 "$X/fullreview.sh" 8 "$SINCE")"
expect "no review at all stops after REVIEW_WAIT polls" "$out" "STOP 8: no full review in 1 polls"

setup; pr 9 APPROVED; checks 9 "$REQ_PASS"; touch "$FAKE_DIR/fail-merge"
out="$("$X/fullreview.sh" 9 "$SINCE")"
expect_has "a refused merge stops" "$out" "STOP 9: merge refused"

echo "fullqueue.sh"
setup; pr 10 APPROVED develop
out="$(cd / && BASE_BRANCH=develop "$X/fullqueue.sh" base:10)"
expect "a PR GitHub already retargeted is left alone" "$out" "already on develop: 10
all done"
expect "with no edit" "$(grep -c 'pr edit' "$FAKE_DIR/log")" "0"

setup; pr 11 APPROVED APPROVED feat/x
out="$(BASE_BRANCH=develop "$X/fullqueue.sh" base:11)"
expect_has "a stacked PR is retargeted" "$out" "retargeted 11"
expect_has "onto the configured base" "$(cat "$FAKE_DIR/log")" "pr edit 11 --repo o/r --base develop"

setup; pr 30 APPROVED APPROVED feat/x; echo develop >"$FAKE_DIR/race-edit-30"
out="$(BASE_BRANCH=develop "$X/fullqueue.sh" base:30 2>&1)"
expect "a retarget that loses the race to GitHub's own carries on (after #543)" "$out" "already on develop: 30 (GitHub retargeted it)
all done"

setup; pr 31 APPROVED APPROVED feat/x; touch "$FAKE_DIR/fail-edit"
out="$(BASE_BRANCH=develop "$X/fullqueue.sh" base:31 2>&1)"
expect "a retarget that fails with the base unchanged stops" "$out" "STOP 31: could not retarget onto develop
REMAINING: base:31"

setup; pr 12 APPROVED
out="$("$X/fullqueue.sh" close:12:13)"
expect_has "close:N:M closes N" "$out" "closed 12"
expect_has "naming its replacement" "$(cat "$FAKE_DIR/log")" "pr close 12 --repo o/r --comment Superseded by #13."

setup; pr 14 none; checks 14 "$REQ_PASS"; pr 15 APPROVED feat/y
out="$(WINDOW=0 REVIEW_WAIT=1 BASE_BRANCH=develop "$X/fullqueue.sh" 14 base:15)"
expect_has "a stop prints the steps left, the stopped PR first" "$out" "REMAINING: 14 base:15"
expect "and runs none of them" "$(grep -c 'pr edit 15' "$FAKE_DIR/log")" "0"

echo "nextpr.sh"
# fresh N: a PR whose review lands after nextpr.sh asks for it
fresh() { jq '.reviews[0].submittedAt = "2099-01-01T00:00:00Z"' "$FAKE_DIR/pr-$1.json" >"$FAKE_DIR/t" && mv "$FAKE_DIR/t" "$FAKE_DIR/pr-$1.json"; }
setup; pr 32 APPROVED; fresh 32; checks 32 "$REQ_PASS"; echo 0 >"$FAKE_DIR/stamp"
out="$("$X/nextpr.sh" 32 3600)"
expect_has "a window that ran out long ago is not slept again" "$out" "merged 32"
log="$(cat "$FAKE_DIR/log")"
expect "the branch is brought up to date while still a draft, before it is marked ready" \
  "$(grep -nE 'pr (update-branch|ready) 32' <<<"$log" | head -2 | sed 's/:.*pr / /' | cut -d' ' -f2 | tr '\n' ' ')" "update-branch update-branch "
expect_has "the review request is recorded" "$(cat "$FAKE_DIR/stamp")" "$(date +%s | cut -c1-6)"

setup; pr 35 APPROVED; fresh 35; checks 35 '[{"name":"build","bucket":"fail","required":true}]'; echo 0 >"$FAKE_DIR/stamp"
out="$("$X/nextpr.sh" 35 3600)"
expect "a PR already red stops before its review is asked for (#588)" "$out" "STOP 35: CI failing before review (no review spent)"
expect "so no review is spent" "$(grep -c 'pr comment 35' "$FAKE_DIR/log")" "0"
expect "and it stays a draft" "$(grep -c 'pr ready 35' "$FAKE_DIR/log")" "0"

setup; pr 33 APPROVED; fresh 33; checks 33 "$REQ_PASS"; date +%s >"$FAKE_DIR/stamp"
start=$SECONDS; "$X/nextpr.sh" 33 2 >/dev/null
expect "a review asked for just now waits out the rest of the window" "$(( SECONDS - start >= 1 ))" "1"

setup; pr 34 APPROVED; fresh 34; checks 34 "$REQ_PASS"; rm -f "$FAKE_DIR/stamp"
start=$SECONDS; "$X/nextpr.sh" 34 2 >/dev/null
expect "with no record of a request it waits the whole window" "$(( SECONDS - start >= 2 ))" "1"

echo "chain.sh"
setup; lone="$(mktemp -d)"; TMPS+=("$lone"); cp "$X/chain.sh" "$lone/"
out="$("$lone/chain.sh" 16)"
expect_has "a missing nextpr.sh stops with where it looked (a /tmp cleaner deleted it once)" "$out" "STOP 16: nextpr.sh missing in $lone"

echo "queue.sh"
Q="$X/../queue.sh"
# qpr N DECISION: a PR whose CodeRabbit review lands after the queue starts (submitted in 2099).
qpr() {
  echo "{\"mergeable\":\"MERGEABLE\",\"reviewDecision\":\"$2\",\"headRefOid\":\"abc\"}" >"$FAKE_DIR/pr-$1.json"
  mkdir -p "$FAKE_DIR/api"
  echo "[{\"user\":{\"login\":\"coderabbitai[bot]\"},\"submitted_at\":\"2099-01-01T00:00:00Z\",\"state\":\"$2\"}]" \
    >"$FAKE_DIR/api/repos_o_r_pulls_$1_reviews.json"
}
setup; qpr 20 APPROVED; checks 20 "[{\"name\":\"build\",\"bucket\":\"pass\",\"required\":true},$DEPENDABOT_QUEUED]"
out="$(SLEEP_SCALE=0 REPO=o/r "$Q" 20)"
expect "queue.sh merges past a check nothing requires (#648)" "$out" "merged 20
queue done"
expect_none "without ever watching that check" "$FAKE_DIR/stalled"

setup; qpr 21 APPROVED; checks 21 '[{"name":"build","bucket":"fail","required":true}]'
out="$(SLEEP_SCALE=0 REPO=o/r "$Q" 21)"
expect "queue.sh stops on a failing required check" "$out" "STOP 21: CI failing"
expect_none "and does not merge" "$FAKE_DIR/merged-21"

setup; qpr 22 APPROVED; checks 22 '[{"name":"build","bucket":"pending","required":true}]'
out="$(SLEEP_SCALE=0 CHECKS_TIMEOUT=0 REPO=o/r "$Q" 22)"
expect_has "queue.sh gives up on a required check that never finishes" "$out" "STOP 22: required checks still pending"

setup; qpr 23 CHANGES_REQUESTED; checks 23 "$REQ_PASS"
out="$(SLEEP_SCALE=0 REPO=o/r "$Q" 23)"
expect "queue.sh stops on changes requested" "$out" "STOP 23: review state=CHANGES_REQUESTED inline=0"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
