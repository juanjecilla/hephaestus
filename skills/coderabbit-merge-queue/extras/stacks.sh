#!/bin/bash
# Group queued PRs into stacks, once, at queue start.
#   stacks.sh 620 624 648
# Prints one line per group, in the order the PRs were given:
#   stack 620 624 648   a PR whose base is another listed PR's head branch, chained
#   solo 593            a PR that neither has nor is a base within the list
# Run it BEFORE the first merge: when a base merges, GitHub retargets its child onto the
# default branch and the stack link is gone from `baseRefName`.
R="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
# bash 3.2 (macOS) has no associative arrays: parallel arrays indexed by position in the list.
nums=("$@"); heads=(); bases=(); parents=()
for i in "${!nums[@]}"; do
  heads[$i]=$(gh pr view "${nums[$i]}" --repo "$R" --json headRefName -q .headRefName)
  bases[$i]=$(gh pr view "${nums[$i]}" --repo "$R" --json baseRefName -q .baseRefName)
  parents[$i]=-1
done
for i in "${!nums[@]}"; do
  for j in "${!nums[@]}"; do
    [ "$i" != "$j" ] && [ "${bases[$i]}" = "${heads[$j]}" ] && parents[$i]=$j
  done
done
for i in "${!nums[@]}"; do
  [ "${parents[$i]}" != -1 ] && continue          # not a root
  chain="${nums[$i]}"; cur=$i; grown=1
  while [ "$grown" = 1 ]; do
    grown=0
    for j in "${!nums[@]}"; do
      if [ "${parents[$j]}" = "$cur" ]; then chain="$chain ${nums[$j]}"; cur=$j; grown=1; break; fi
    done
  done
  case "$chain" in *" "*) echo "stack $chain" ;; *) echo "solo $chain" ;; esac
done
