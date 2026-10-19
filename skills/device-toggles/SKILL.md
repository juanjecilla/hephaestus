---
name: device-toggles
description: Switch Android accessibility settings over adb (TalkBack, font scale, display size, animations, high-contrast text, colour inversion, colour-blindness filters) and capture screenshots or recordings, then reset everything. Use when auditing or demoing an Android app under an accessibility setting, reproducing "it breaks at 200% text", preparing a TalkBack walk-through, or restoring a device after testing.
license: Apache-2.0
---

# device-toggles

One script, `scripts/a11y-device.sh`, so an agent (or you) can put a device in the state a real user is in, and take it back.

```bash
S=skills/device-toggles/scripts/a11y-device.sh
$S status
$S font-scale 2.0         # the setting low-vision users change first
$S density 540            # "display size" larger: the other half
$S talkback on            # needs the TalkBack package (Google Play images, real devices)
$S animations off         # what reduce-motion users get
$S daltonizer deuteranomaly
$S shot out/font2.png
$S record out/talkback.mp4 20
$S reset                  # always leave the device clean
```

Pick the device with `ANDROID_SERIAL=<serial>` when several are attached.

## When to use it

- Before `a11y-audit` dynamic checks: dump the tree at 1.0 and at 2.0 font scale and compare.
- To record the before/after clip of a talk or a bug report.
- After any session: `reset`.

## Rules

1. **Always `reset`** at the end. These are global device settings, not per app.
2. Do not run it on a device someone else is using. An emulator or a test device is the default.
3. Dismiss system dialogs (ANR, permission prompts) before dumping the tree: an overlay hides the app's nodes and the audit reports ghosts.
4. TalkBack changes how the device behaves (first tap selects, double tap activates). Switch it off before driving the UI with `adb shell input tap`.
5. `animations off` sets the three global scales to 0; apps that read `ANIMATOR_DURATION_SCALE` honour it, apps with hard-coded durations do not: that is itself a finding.

## What it cannot do

Switch Access and Voice Access have no portable adb switch (their service component differs per device). Enable them by hand and note it in the report.
