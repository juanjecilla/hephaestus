#!/bin/bash
# One sequential merge queue. Each step is one of:
#   N              run PR N through chain.sh (wait a window, review, merge on approval + required checks)
#   base:N         retarget stacked PR N to the default branch (no-op if GitHub already did)
#   close:N:M      close PR N as superseded by M (after M merged)
# Stops at the first failure and prints `REMAINING: …`, so a restart is that one line.
D="$(cd "$(dirname "$0")" && pwd)"
R="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
BASE="${BASE_BRANCH:-$(gh repo view "$R" --json defaultBranchRef -q .defaultBranchRef.name)}"
steps=("$@")
for i in "${!steps[@]}"; do
  s=${steps[$i]}
  case "$s" in
    base:*)
      n=${s#base:}
      # GitHub retargets a stacked PR by itself when its base branch is deleted on merge.
      if [ "$(gh pr view "$n" --repo "$R" --json baseRefName -q .baseRefName)" = "$BASE" ]; then
        echo "already on $BASE: $n"
      else
        gh pr edit "$n" --repo "$R" --base "$BASE" >/dev/null && echo "retargeted $n"
      fi ;;
    close:*)
      IFS=: read -r _ n m <<<"$s"
      gh pr close "$n" --repo "$R" --comment "Superseded by #$m." >/dev/null && echo "closed $n" ;;
    *) "$D/chain.sh" "$s" ;;
  esac || { echo "REMAINING: ${steps[*]:$i}"; exit 1; }
done
echo "all done"
