#!/usr/bin/env bash
# Dump the accessibility tree of the foreground screen and save it with the display density.
# Usage: dump_tree.sh <out-dir> [name]   → <out-dir>/<name>.xml and <out-dir>/<name>.density
# Compose draws no Views, but its semantics are exposed to UiAutomator: text, content-desc, clickable, bounds.
set -euo pipefail
out="${1:?output dir required}"; name="${2:-screen}"
ADB=(adb); [ -n "${ANDROID_SERIAL:-}" ] && ADB=(adb -s "$ANDROID_SERIAL")
mkdir -p "$out"
# uiautomator prints "ERROR: null root node" (exit 0) while a window animates or an animation never settles: retry
for try in 1 2 3; do
  res=$("${ADB[@]}" shell uiautomator dump /sdcard/a11y-window.xml 2>&1 || true)
  case "$res" in *ERROR*) sleep 1.5 ;; *) break ;; esac
done
case "$res" in *ERROR*) echo "dump failed after 3 tries: $res" >&2; exit 1 ;; esac
"${ADB[@]}" pull -q /sdcard/a11y-window.xml "$out/$name.xml"
"${ADB[@]}" shell rm /sdcard/a11y-window.xml
# "Physical density: 420" (+ "Override density: 600" when changed): the override wins
"${ADB[@]}" shell wm density | awk '/density/ {d=$NF} END {print d}' > "$out/$name.density"
echo "$out/$name.xml (density $(cat "$out/$name.density"))"
