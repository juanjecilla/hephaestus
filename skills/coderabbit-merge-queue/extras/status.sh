#!/bin/bash
# Says what the queue is doing from its record (fullqueue.sh writes it at start and at every exit).
#   status.sh [record]      default: $QUEUE_EXIT_FILE, else last-exit next to this script
# Prints RUNNING / DONE / STOPPED / DIED. Exit 0 for RUNNING and DONE; 1 otherwise, so a poll notices.
# DIED = the record says running but its process is gone (killed, or crashed before it could record).
F="${1:-${QUEUE_EXIT_FILE:-$(cd "$(dirname "$0")" && pwd)/last-exit}}"
[ -r "$F" ] || { echo "NO RECORD: $F (no queue has run from here)"; exit 1; }
get() { sed -n "s/^$1=//p" "$F" | head -1; }
status=$(get status); at=$(get at)
case "$status" in
  running)
    pid=$(get pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "RUNNING since $at (pid $pid)"
    else echo "DIED: recorded as running since $at but pid ${pid:-?} is gone"; exit 1; fi ;;
  done) echo "DONE at $at" ;;
  stopped)
    echo "STOPPED at $at"; echo "$(get stop)"; echo "left: $(get remaining)"; exit 1 ;;
  *) echo "UNKNOWN record in $F"; exit 1 ;;
esac
