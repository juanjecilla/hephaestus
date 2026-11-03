#!/bin/bash
# usage: nextpr.sh PR [WINDOW] — wait out the review window, ask for a full review, merge only on APPROVED.
# Env: REPO (owner/name, else the cwd's), STAMP (file holding when this queue last asked for a review).
#
# The window runs from the last review request, not from the last merge. Sleeping a full WINDOW after
# each merge put the previous PR's CI wait on top of the window: #693 merged at 06:14, #543 was asked
# at 07:14, approved at 07:23 and then waited 35 more minutes for the CI its update-branch started.
pr=$1; window=${2:-3600}; D="$(cd "$(dirname "$0")" && pwd)"
R="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
STAMP="${STAMP:-$D/.last-request-${R//\//_}}"
# The PR is still a draft here, so this push spends no review, and its CI runs during the wait.
gh pr update-branch "$pr" --repo "$R" >/dev/null 2>&1
last=$(cat "$STAMP" 2>/dev/null || true)
if [[ "$last" =~ ^[0-9]+$ ]]; then wait=$((last + window - $(date +%s))); else wait=$window; fi
[ "$wait" -gt "$window" ] && wait=$window
[ "$wait" -gt 0 ] && sleep "$wait"
# Again, in case the base moved during the wait (still a draft, still free).
gh pr update-branch "$pr" --repo "$R" >/dev/null 2>&1
gh pr ready "$pr" --repo "$R" >/dev/null 2>&1
since=$(date -u -d '-1 min' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)
gh pr comment "$pr" --repo "$R" --body "@coderabbitai full review" >/dev/null && date +%s >"$STAMP"
"$D/fullreview.sh" "$pr" "$since"
