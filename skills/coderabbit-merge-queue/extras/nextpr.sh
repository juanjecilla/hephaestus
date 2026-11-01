#!/bin/bash
# usage: nextpr.sh PR [SLEEP] — wait a review window, ask for a full review, merge only on APPROVED.
pr=$1; D="$(cd "$(dirname "$0")" && pwd)"
sleep "${2:-3600}"
gh pr update-branch "$pr" >/dev/null 2>&1
gh pr ready "$pr" >/dev/null 2>&1
since=$(date -u -d '-1 min' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)
gh pr comment "$pr" --body "@coderabbitai full review" >/dev/null
"$D/fullreview.sh" "$pr" "$since"
