#!/bin/bash
# Runs nextpr.sh over the given PRs in order; stops at the first STOP.
D="$(cd "$(dirname "$0")" && pwd)"
for pr in "$@"; do
  [ -x "$D/nextpr.sh" ] || { echo "STOP $pr: nextpr.sh missing in $D"; exit 1; }
  "$D/nextpr.sh" "$pr" "${WINDOW:-3600}" || exit 1
done
echo "queue done"
