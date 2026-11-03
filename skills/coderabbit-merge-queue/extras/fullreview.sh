#!/bin/bash
# usage: fullreview.sh PR SINCE_ISO — wait for CodeRabbit's review after SINCE, then merge on approval.
# Env: POLL (seconds between polls, 60), REVIEW_WAIT (polls before giving up on a review, 60),
#      RESOLVE_WAIT (seconds after `@coderabbitai resolve`, 120),
#      CHECKS_TIMEOUT (seconds to wait for required checks, 5400), MERGE_FLAGS (--squash),
#      RATE_RETRY_MAX (longest stated rate-limit wait to sit out and ask again, 900),
#      RATE_MARGIN (seconds added to that wait, 60), STAMP (nextpr.sh's request record).
pr=$1; since=$2
POLL="${POLL:-60}"

# Waits for the PR's *required* checks only. A check nothing requires can sit "queued" forever
# (GitHub's own `.github/dependabot.yml` check did, for 39 hours on #648), and waiting on every
# check with no timeout stalled the whole queue behind it.
wait_required_checks() {
  local deadline=$((SECONDS + ${CHECKS_TIMEOUT:-5400})) buckets
  while :; do
    buckets="$(gh pr checks "$pr" --required --json bucket -q '.[].bucket' 2>/dev/null)"
    if grep -qE 'fail|cancel' <<<"$buckets"; then echo "STOP $pr: CI failing"; return 1; fi
    grep -q pending <<<"$buckets" || return 0
    if [ "$SECONDS" -ge "$deadline" ]; then echo "STOP $pr: required checks still pending after ${CHECKS_TIMEOUT:-5400}s"; return 1; fi
    sleep "$POLL"
  done
}

# Seconds CodeRabbit's newest rate-limit reply says to wait ("available in 1 minute and 5 seconds"), or empty.
stated_wait() {
  gh pr view "$pr" --json comments -q "[.comments[]|select(.author.login==\"coderabbitai\" and .createdAt>\"$since\" and (.body|test(\"Review limit reached|rate limit\")))]|last|.body // empty" \
    | grep -oE 'available in [0-9a-z ,]+' | grep -oE '[0-9]+ (hour|minute|second)' \
    | awk '/hour/{t+=$1*3600} /minute/{t+=$1*60} /second/{t+=$1} END{if (NR) print t}'
}

st=""; retried=""
for _ in $(seq 1 "${REVIEW_WAIT:-60}"); do
  sleep "$POLL"
  st=$(gh pr view "$pr" --json reviews -q "[.reviews[]|select(.author.login==\"coderabbitai\" and .submittedAt>\"$since\")|.state]|last // empty")
  [ -n "$st" ] && break
  rl=$(gh pr view "$pr" --json comments -q "[.comments[]|select(.author.login==\"coderabbitai\" and .createdAt>\"$since\" and (.body|test(\"Review limit reached|rate limit\")))]|length")
  if [ "$rl" != "0" ]; then
    # The limit reply can land seconds after an approval of the head (#512): that approval stands.
    # shellcheck disable=SC2016 # $h is jq's, not the shell's
    head_ok=$(gh pr view "$pr" --json headRefOid,reviews -q '.headRefOid as $h|[.reviews[]|select(.author.login=="coderabbitai")]|last|(.state=="APPROVED" and .commit.oid==$h)')
    [ "$head_ok" = "true" ] && { st=APPROVED; break; }
    # A short stated wait is the window's edge: CodeRabbit counts the hour from its own reply, a minute
    # or so after the request (#588 was refused with 37 seconds to go). Sit it out and ask once more.
    wait_s="$(stated_wait)"
    if [ -z "$retried" ] && [ -n "$wait_s" ] && [ "$wait_s" -le "${RATE_RETRY_MAX:-900}" ]; then
      retried=1; sleep $((wait_s + ${RATE_MARGIN:-60}))
      since=$(date -u -d '-1 min' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)
      gh pr comment "$pr" --body "@coderabbitai full review" >/dev/null && { [ -n "${STAMP:-}" ] && date +%s >"$STAMP"; }
      continue
    fi
    echo "STOP $pr: rate limited (full review)"; exit 1
  fi
  # "Full review finished" with nothing new posts no review: fall back to the standing decision.
  fin=$(gh pr view "$pr" --json comments -q "[.comments[]|select(.author.login==\"coderabbitai\" and .createdAt>\"$since\" and (.body|test(\"Full review finished\")))]|length")
  if [ "$fin" != "0" ]; then
    st=$(gh pr view "$pr" --json reviewDecision -q .reviewDecision); [ "$st" = "APPROVED" ] && break
    gh pr comment "$pr" --body "@coderabbitai resolve" >/dev/null; sleep "${RESOLVE_WAIT:-120}"
    st=$(gh pr view "$pr" --json reviewDecision -q .reviewDecision); break
  fi
done
[ -z "$st" ] && { echo "STOP $pr: no full review in ${REVIEW_WAIT:-60} polls"; exit 1; }
echo "review $pr: $st"
# Anything short of an approval needs a fix; waiting longer would only wait for a newer review.
if [ "$st" != "APPROVED" ] && [ "$(gh pr view "$pr" --json reviewDecision -q .reviewDecision)" != "APPROVED" ]; then
  echo "STOP $pr: review state=$st"; exit 1
fi
wait_required_checks || exit 1
# shellcheck disable=SC2086
gh pr merge "$pr" ${MERGE_FLAGS:---squash} >/dev/null || { echo "STOP $pr: merge refused"; exit 1; }
echo "merged $pr"
