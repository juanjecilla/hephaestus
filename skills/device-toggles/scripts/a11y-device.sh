#!/usr/bin/env bash
# Toggle the Android accessibility settings an audit or a demo needs, over adb. Reversible: `reset` restores defaults.
# Usage: a11y-device.sh <command> [value]     (set ADB_SERIAL or pass -s via ANDROID_SERIAL to pick a device)
set -euo pipefail

ADB=(adb)
[ -n "${ANDROID_SERIAL:-}" ] && ADB=(adb -s "$ANDROID_SERIAL")
sh() { "${ADB[@]}" shell "$@"; }

TALKBACK=com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService

usage() {
  cat <<USAGE
a11y-device.sh <command> [value]

  status                 print the current values
  talkback on|off        enable/disable TalkBack (must be installed: Google Play images and real devices)
  font-scale <x>         text size multiplier, e.g. 1.0, 1.3, 2.0 (the Settings maximum is ~2.0 on Android 14+)
  animations on|off      window/transition/animator scales 1 ↔ 0 (what "reduce motion" implies for most apps)
  high-contrast on|off   high contrast text
  invert on|off          colour inversion
  daltonizer <mode>      off | protanomaly | deuteranomaly | tritanomaly | monochrome
  density <dpi>|reset    display size (the other half of "make everything bigger")
  shot <file.png>        screenshot
  record <file.mp4> [s]  screen recording (default 20 s, max 180)
  reset                  everything above back to defaults
USAGE
}

on_off() { case "$1" in on|1|true) echo 1 ;; off|0|false) echo 0 ;; *) echo "expected on|off" >&2; exit 2 ;; esac; }

cmd="${1:-}"; shift || true
case "$cmd" in
  status)
    echo "font_scale:            $(sh settings get system font_scale)"
    echo "animations (w/t/a):    $(sh settings get global window_animation_scale) / $(sh settings get global transition_animation_scale) / $(sh settings get global animator_duration_scale)"
    echo "high contrast text:    $(sh settings get secure high_text_contrast_enabled)"
    echo "colour inversion:      $(sh settings get secure accessibility_display_inversion_enabled)"
    echo "daltonizer enabled:    $(sh settings get secure accessibility_display_daltonizer_enabled) (mode $(sh settings get secure accessibility_display_daltonizer))"
    echo "a11y services:         $(sh settings get secure enabled_accessibility_services)"
    echo "density:               $(sh wm density | tr '\n' ' ')"
    ;;
  talkback)
    v=$(on_off "${1:-}")
    if [ "$v" = 1 ]; then
      sh pm list packages com.google.android.marvin.talkback | grep -q talkback || { echo "TalkBack is not installed on this device/image" >&2; exit 3; }
      sh settings put secure enabled_accessibility_services "$TALKBACK"
      sh settings put secure accessibility_enabled 1
    else
      sh settings put secure enabled_accessibility_services ""
      sh settings put secure accessibility_enabled 0
    fi ;;
  font-scale) sh settings put system font_scale "${1:?scale required}" ;;
  animations)
    s=$(on_off "${1:-}")   # on = scale 1, off = scale 0
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do sh settings put global "$k" "$s"; done ;;
  high-contrast) sh settings put secure high_text_contrast_enabled "$(on_off "${1:-}")" ;;
  invert) sh settings put secure accessibility_display_inversion_enabled "$(on_off "${1:-}")" ;;
  daltonizer)
    case "${1:-}" in
      off) sh settings put secure accessibility_display_daltonizer_enabled 0 ;;
      monochrome) sh settings put secure accessibility_display_daltonizer_enabled 1; sh settings put secure accessibility_display_daltonizer 0 ;;
      protanomaly) sh settings put secure accessibility_display_daltonizer_enabled 1; sh settings put secure accessibility_display_daltonizer 11 ;;
      deuteranomaly) sh settings put secure accessibility_display_daltonizer_enabled 1; sh settings put secure accessibility_display_daltonizer 12 ;;
      tritanomaly) sh settings put secure accessibility_display_daltonizer_enabled 1; sh settings put secure accessibility_display_daltonizer 13 ;;
      *) echo "off|protanomaly|deuteranomaly|tritanomaly|monochrome" >&2; exit 2 ;;
    esac ;;
  density) if [ "${1:-}" = reset ]; then sh wm density reset; else sh wm density "${1:?dpi required}"; fi ;;
  shot) "${ADB[@]}" exec-out screencap -p > "${1:?output file required}"; echo "saved ${1}" ;;
  record)
    out="${1:?output file required}"; secs="${2:-20}"
    sh screenrecord --time-limit "$secs" /sdcard/a11y-record.mp4
    "${ADB[@]}" pull -q /sdcard/a11y-record.mp4 "$out"; sh rm /sdcard/a11y-record.mp4; echo "saved $out" ;;
  reset)
    sh settings put system font_scale 1.0
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do sh settings put global "$k" 1; done
    sh settings put secure high_text_contrast_enabled 0
    sh settings put secure accessibility_display_inversion_enabled 0
    sh settings put secure accessibility_display_daltonizer_enabled 0
    sh settings put secure enabled_accessibility_services ""
    sh settings put secure accessibility_enabled 0
    sh wm density reset
    echo "reset done" ;;
  ""|-h|--help|help) usage ;;
  *) echo "unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
