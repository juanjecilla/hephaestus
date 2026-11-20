#!/bin/bash
# usage: nextpr.sh PR [WINDOW] — wait out the review window, ask for a full review, merge only on APPROVED.
# Env: REPO (owner/name, else the cwd's), STAMP (file holding when this queue last asked for a review),
#      MARGIN (seconds added to the window, 180: CodeRabbit starts its hour at its own reply, not at ours),
#      MERGEABLE_POLL (seconds between asks while GitHub reports mergeable UNKNOWN, 10).
#
# The window runs from the last review request, not from the last merge. Sleeping a full WINDOW after
# each merge put the previous PR's CI wait on top of the window: #693 merged at 06:14, #543 was asked
# at 07:14, approved at 07:23 and then waited 35 more minutes for the CI its update-branch started.
pr=$1; window=${2:-3600}; D="$(cd "$(dirname "$0")" && pwd)"
R="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
STAMP="${STAMP:-${MERGE_QUEUE_HOME:-$HOME/.cache/merge-queue-run}/.last-request-${R//\//_}}"
# The PR is still a draft here, so this push spends no review, and its CI runs during the wait.
gh pr update-branch "$pr" --repo "$R" >/dev/null 2>&1
last=$(cat "$STAMP" 2>/dev/null || true)
margin=${MARGIN:-180}; [ "$window" -eq 0 ] && margin=0
if [[ "$last" =~ ^[0-9]+$ ]]; then wait=$((last + window + margin - $(date +%s))); else wait=$((window + margin)); fi
[ "$wait" -gt $((window + margin)) ] && wait=$((window + margin))
[ "$wait" -gt 0 ] && sleep "$wait"
# A required check that already failed fails the merge whatever the review says: stop before the
# review is spent. #588 went red at 08:29 and was reviewed three more times before anything noticed.
if gh pr checks "$pr" --repo "$R" --required --json bucket -q '.[].bucket' 2>/dev/null | grep -qE 'fail|cancel'; then
  echo "STOP $pr: CI failing before review (no review spent)"; exit 1
fi
# Again, in case the base moved during the wait (still a draft, still free).
gh pr update-branch "$pr" --repo "$R" >/dev/null 2>&1
# A conflict makes update-branch fail quietly and the merge refuse after the approval: stop first.
# #684 and #558 each spent a review and were then refused, because the PR merged ahead of them
# touched the same lines. GitHub answers UNKNOWN while it recomputes after a push; ask again.
for _ in 1 2 3 4 5 6; do
  m=$(gh pr view "$pr" --repo "$R" --json mergeable -q .mergeable 2>/dev/null)
  [ "$m" = UNKNOWN ] || break; sleep "${MERGEABLE_POLL:-10}"
done
if [ "$m" = CONFLICTING ]; then echo "STOP $pr: merge conflict with base (no review spent)"; exit 1; fi
gh pr ready "$pr" --repo "$R" >/dev/null 2>&1
since=$(date -u -d '-1 min' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)
gh pr comment "$pr" --repo "$R" --body "@coderabbitai full review" >/dev/null && date +%s >"$STAMP"
STAMP="$STAMP" "$D/fullreview.sh" "$pr" "$since"
