#!/bin/bash
# CodeRabbit-paced merge queue: one PR per review window, merge only on a
# clean approval with green CI, stop (exit 1, "STOP <pr>: <reason>") on
# anything else so a human or agent can fix it and restart from that PR.
#
#   queue.sh 263 264 265            # sleeps one window before the first PR
#   NO_FIRST_SLEEP=1 queue.sh 263   # start now (last review was > a window ago)
#
# Env:
#   REPO           owner/name (default: the current checkout's repo)
#   WINDOW         seconds between reviews (default 3600: CodeRabbit's free OSS plan)
#   REQUEST_AFTER  minutes to wait for an automatic review before asking (default 10)
#   REVIEW_WAIT    minutes to wait for a review at all (default 90)
#   MERGE_FLAGS    gh pr merge flags (default --squash)
#   CHECKS_TIMEOUT seconds to wait for the required checks (default 5400)
#   SLEEP_SCALE    multiplies every pause; 0 in the tests (default 1)
set -u
nap() { sleep "$(( $1 * ${SLEEP_SCALE:-1} ))"; }
R="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
WINDOW="${WINDOW:-3600}"
REQUEST_AFTER="${REQUEST_AFTER:-10}"
REVIEW_WAIT="${REVIEW_WAIT:-90}"
MERGE_FLAGS="${MERGE_FLAGS:---squash}"

# Only the checks the base branch *requires*: an optional check can sit "queued" forever
# (GitHub's own `.github/dependabot.yml` check did, for 39 hours), and an unbounded
# `gh pr checks --watch` on every check stalled the whole queue behind it.
wait_required_checks() {
  local pr="$1" deadline=$((SECONDS + ${CHECKS_TIMEOUT:-5400})) buckets
  while :; do
    buckets="$(gh pr checks "$pr" -R "$R" --required --json bucket --jq '.[].bucket' 2>/dev/null)"
    if grep -qE 'fail|cancel' <<<"$buckets"; then echo "STOP $pr: CI failing"; return 1; fi
    grep -q pending <<<"$buckets" || return 0
    if [ "$SECONDS" -ge "$deadline" ]; then echo "STOP $pr: required checks still pending after ${CHECKS_TIMEOUT:-5400}s"; return 1; fi
    nap 60
  done
}
BOT='coderabbit'

first=1
for pr in "$@"; do
  if [ -n "$first" ] && [ -n "${NO_FIRST_SLEEP:-}" ]; then :; else nap "$WINDOW"; fi
  first=

  # Up to date with the base, so required checks run on the merged result.
  st=$(gh pr view "$pr" -R "$R" --json mergeable --jq .mergeable)
  for _ in 1 2 3 4 5; do
    [ "$st" = UNKNOWN ] || break
    nap 20; st=$(gh pr view "$pr" -R "$R" --json mergeable --jq .mergeable)
  done
  [ "$st" = CONFLICTING ] && { echo "STOP $pr: merge conflict with base"; exit 1; }
  gh pr update-branch "$pr" -R "$R" >/dev/null 2>&1

  n=0
  start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Marking a draft ready usually triggers the review, but not always (and a
  # PR that was already ready triggers nothing), so ask explicitly if no
  # review has started after REQUEST_AFTER minutes. Asking immediately on top
  # of the automatic one would spend two reviews from the window.
  gh pr ready "$pr" -R "$R" >/dev/null 2>&1
  for i in $(seq 1 "$REVIEW_WAIT"); do
    nap 60
    [ "$i" -eq "$REQUEST_AFTER" ] && [ "$n" -eq 0 ] \
      && gh pr comment "$pr" -R "$R" --body "@coderabbitai review" >/dev/null
    n=$(gh api "repos/$R/pulls/$pr/reviews" --jq "[.[]|select(.user.login|test(\"$BOT\"))|select(.submitted_at>\"$start\")]|length")
    rl=$(gh api "repos/$R/issues/$pr/comments" --jq "[.[]|select(.user.login|test(\"$BOT\"))|select(.updated_at>\"$start\")|select(.body|test(\"Review limit reached|rate limit\";\"i\"))]|length")
    [ "$rl" -gt 0 ] && { echo "STOP $pr: rate limited"; exit 1; }
    [ "$n" -gt 0 ] && break
    # A re-review that finds nothing new posts no review at all: it answers
    # "Already reviewed the last commit" or just sets its commit status to
    # "Review completed". The earlier CHANGES_REQUESTED then still blocks;
    # resolving its comments is what makes CodeRabbit flip the decision.
    head=$(gh pr view "$pr" -R "$R" --json headRefOid --jq .headRefOid)
    done_=$(gh api "repos/$R/commits/$head/status" --jq '[.statuses[]|select(.context|test("CodeRabbit"))|select(.description|test("completed";"i"))]|length')
    if [ "$done_" -gt 0 ]; then
      # The status can land a moment before a real review's objects do.
      nap 90
      n=$(gh api "repos/$R/pulls/$pr/reviews" --jq "[.[]|select(.user.login|test(\"$BOT\"))|select(.submitted_at>\"$start\")]|length")
      [ "$n" -gt 0 ] && break
      if [ "$(gh pr view "$pr" -R "$R" --json reviewDecision --jq .reviewDecision)" = CHANGES_REQUESTED ]; then
        # Never resolve away findings nobody answered: a resolve flips the decision to APPROVED.
        unanswered=$(gh api "repos/$R/pulls/$pr/comments" --paginate --jq '.[]' | jq -s --arg bot "$BOT" '
          ([.[]|select(.in_reply_to_id!=null and (.user.login|test($bot)|not))|.in_reply_to_id]) as $answered
          | [.[]|select(.in_reply_to_id==null and (.user.login|test($bot)))|select(.id as $i|$answered|index($i)|not)]|length')
        [ "$unanswered" != 0 ] && { echo "STOP $pr: review state=CHANGES_REQUESTED inline=$unanswered unanswered"; exit 1; }
        gh pr comment "$pr" -R "$R" --body "@coderabbitai resolve" >/dev/null
        for _ in $(seq 1 15); do
          nap 60
          [ "$(gh pr view "$pr" -R "$R" --json reviewDecision --jq .reviewDecision)" = APPROVED ] && break
        done
      fi
      n=1; silent=1; break
    fi
  done
  [ "$n" -gt 0 ] || { echo "STOP $pr: no review in $REVIEW_WAIT min"; exit 1; }

  nap 30   # inline comments land just after the review object
  if [ -n "${silent:-}" ]; then
    state=$(gh pr view "$pr" -R "$R" --json reviewDecision --jq .reviewDecision); silent=
  else
    state=$(gh api "repos/$R/pulls/$pr/reviews" --jq "[.[]|select(.user.login|test(\"$BOT\"))|select(.submitted_at>\"$start\")]|last|.state")
  fi
  inline=$(gh api "repos/$R/pulls/$pr/comments" --jq "[.[]|select(.created_at>\"$start\")]|length")
  # A re-review with nothing to add is COMMENTED while the PR stays APPROVED.
  if [ "$state" = COMMENTED ] \
    && [ "$(gh pr view "$pr" -R "$R" --json reviewDecision --jq .reviewDecision)" = APPROVED ]; then
    state=APPROVED
  fi
  { [ "$state" = APPROVED ] && [ "$inline" -eq 0 ]; } \
    || { echo "STOP $pr: review state=$state inline=$inline"; exit 1; }

  wait_required_checks "$pr" || exit 1
  # shellcheck disable=SC2086
  if gh pr merge "$pr" -R "$R" $MERGE_FLAGS >/dev/null; then echo "merged $pr"; else echo "STOP $pr: merge refused"; exit 1; fi
done
echo "queue done"
