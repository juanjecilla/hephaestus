#!/bin/bash
# One sequential merge queue. Each step is one of:
#   N              run PR N through chain.sh (wait a window, review, merge on approval + required checks)
#   base:N         retarget stacked PR N to the default branch (no-op if GitHub already did)
#   close:N:M      close PR N as superseded by M (after M merged)
# Stops at the first failure and prints `REMAINING: …`, so a restart is that one line.
D="$(cd "$(dirname "$0")" && pwd)"
# Only a tracked background task wakes the session when the queue stops. A `nohup … &` start
# returns at once and its STOP fires nothing (a Muviss queue sat stopped for hours that way).
# The documented start line sets QUEUE_TRACKED=1; QUEUE_DETACHED_OK=1 is the deliberate opt-out.
if [ "${QUEUE_TRACKED:-}" != 1 ] && [ "${QUEUE_DETACHED_OK:-}" != 1 ]; then
  echo "refusing to start: run this as a background command (run_in_background: true) with QUEUE_TRACKED=1," >&2
  echo "never nohup/& (its STOP would fire no notification). QUEUE_DETACHED_OK=1 overrides on purpose." >&2
  exit 2
fi
R="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
BASE="${BASE_BRANCH:-$(gh repo view "$R" --json defaultBranchRef -q .defaultBranchRef.name)}"
export REPO="$R"
steps=("$@")
# What this process printed, so the exit record can name the STOP line.
EXIT_FILE="${QUEUE_EXIT_FILE:-$D/last-exit}"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
set -o pipefail
say() { echo "$*" | tee -a "$LOG"; }
record_exit() { # status remaining
  printf 'status=%s\nat=%s\nstop=%s\nremaining=%s\n' "$1" "$(date -u +%FT%TZ)" \
    "$(grep '^STOP' "$LOG" | tail -1)" "$2" >"$EXIT_FILE"
  notify "$1" "$2"
}
# A detached queue fires no task notification, so tell the person ourselves.
# QUEUE_NOTIFY_CMD runs under bash with the message as $1 (unset: macOS notification if osascript exists); a failing hook never changes the exit code.
notify() { # status remaining
  local msg; if [ "$1" = done ]; then msg="Merge queue: all done"; else
    msg="$(grep '^STOP' "$LOG" | tail -1) (left: $2)"; fi
  if [ "${QUEUE_NOTIFY_CMD+set}" ]; then   # set, even empty, wins; empty switches it off
    [ -n "$QUEUE_NOTIFY_CMD" ] && { bash -c "$QUEUE_NOTIFY_CMD" _ "$msg" >/dev/null 2>&1 || true; }
  elif command -v osascript >/dev/null 2>&1; then
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Merge queue"' \
      -e 'end run' "$msg" >/dev/null 2>&1 || true
  fi
  return 0
}
# A sleeping Mac stalls every wait and can swallow the stop banner; hold it awake while this process lives.
if [ "${QUEUE_NO_CAFFEINATE:-}" != 1 ] && command -v caffeinate >/dev/null 2>&1; then
  caffeinate -i -w "$$" >/dev/null 2>&1 &
fi
printf 'status=running\npid=%s\nat=%s\n' "$$" "$(date -u +%FT%TZ)" >"$EXIT_FILE"
for i in "${!steps[@]}"; do
  s=${steps[$i]}
  case "$s" in
    base:*)
      n=${s#base:}
      # GitHub retargets a stacked PR by itself when its base branch is deleted on merge.
      # It does so seconds after the merge, so a check made right after can still see the old base
      # and the edit then collides with GitHub's ("A pull request already exists", after #543).
      base_of() { gh pr view "$n" --repo "$R" --json baseRefName -q .baseRefName; }
      if [ "$(base_of)" = "$BASE" ]; then
        say "already on $BASE: $n"
      elif gh pr edit "$n" --repo "$R" --base "$BASE" >/dev/null 2>&1; then
        say "retargeted $n"
      else
        sleep "${RETARGET_WAIT:-15}"
        [ "$(base_of)" = "$BASE" ] && say "already on $BASE: $n (GitHub retargeted it)" \
          || { say "STOP $n: could not retarget onto $BASE"; false; }
      fi ;;
    close:*)
      IFS=: read -r _ n m <<<"$s"
      gh pr close "$n" --repo "$R" --comment "Superseded by #$m." >/dev/null && say "closed $n" ;;
    *) "$D/chain.sh" "$s" | tee -a "$LOG" ;;
  esac || { say "REMAINING: ${steps[*]:$i}"; record_exit stopped "${steps[*]:$i}"; exit 1; }
done
say "all done"
record_exit done ""
