#!/usr/bin/env bash
# Scan only the Kotlin files a branch changed, and show only the findings on lines the branch added or touched.
# Usage: scan_diff.sh [base-ref]      (default: origin/main)
set -euo pipefail
base="${1:-origin/main}"
here="$(cd "$(dirname "$0")" && pwd)"
scan="$here/../../a11y-audit/scripts/scan_compose.py"
[ -f "$scan" ] || { echo "a11y-audit not found next to this skill: $scan" >&2; exit 2; }

files=$(git diff --name-only --diff-filter=AM "$base"...HEAD -- '*.kt' | grep -v -E '/(build|test|androidTest|commonTest|jvmTest)/|Test\.kt$' || true)
[ -z "$files" ] && { echo "no changed Kotlin sources"; exit 0; }

status=0
for f in $files; do
  [ -f "$f" ] || continue
  # lines added by the branch in this file
  added=$(git diff -U0 "$base"...HEAD -- "$f" | awk '/^@@/ { split($3, a, ","); s = substr(a[1], 2) + 0; n = (a[2] == "" ? 1 : a[2] + 0); for (i = 0; i < n; i++) print s + i }' | tr '\n' ' ')
  python3 "$scan" "$f" --json | python3 -c '
import json, sys
added = set(map(int, sys.argv[1].split()))
hits = [h for h in json.load(sys.stdin) if h["line"] in added]
for h in hits:
    print(f'"'"'{h["severity"]:7} {h["rule"]:19} {h["person"]:9} {h["file"]}:{h["line"]}  {h["why"]}'"'"')
sys.exit(1 if any(h["severity"] == "error" for h in hits) else 0)
' "$added" || status=1
done
exit $status
