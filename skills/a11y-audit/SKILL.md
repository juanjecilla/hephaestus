---
name: a11y-audit
description: Audit an Android (Jetpack Compose or Compose Multiplatform) app for accessibility, from the code and from a running device, and report findings per person affected (blind, low vision, cognitive, motor) with severity and file:line. Use when asked to audit, review or "check the a11y" of an Android app, screen or PR, before fixing anything, or to build a before/after report.
license: Apache-2.0
---

# a11y-audit

Find the problems first, with evidence, and say who each one hurts. Fixing is `a11y-fix`.

## Method

1. **Static scan** of the sources (finds what a device cannot see):
   `python3 skills/a11y-audit/scripts/scan_compose.py <module-or-dir>` → missing labels, sub-48 dp targets, gesture-only controls, text in dp, 11 sp text, hard-coded colours.
2. **Dynamic scan** of each screen that matters (finds what the code does not say):
   ```bash
   skills/a11y-audit/scripts/dump_tree.sh out search
   python3 skills/a11y-audit/scripts/tree_audit.py out/search.xml --density $(cat out/search.density)
   python3 skills/talkback-speak/scripts/speak.py out/search.xml      # what a blind user would hear
   ```
3. **Under settings**, with `device-toggles`: repeat at `font-scale 2.0` and `density` larger. Look for clipped text, overlapping, truncated labels, targets pushed off screen.
4. **Contrast** with `contrast-check` (`theme`, `literals`).
5. **Read the code behind every finding.** The scans are heuristics. Confirm, discard false positives, and add what they cannot see: heading structure, traversal order, state announcements, custom actions for swipes, live regions.
6. **Write the report**: one table per person; each row `severity · rule · where (file:line or screen) · what the user experiences · suggested fix`. Include the evidence (tree excerpt, `speak.py` line, screenshot).

## Rules

- **Verify every finding before you report or fix it.** In the talk's own audit the static scan raised four errors and none was a real bug (three decorative icons beside text, and a 24 dp button whose touch area Compose had already made 48 dp), and the agent itself reported two motor findings that the code contradicted. Prove it with a test or the device, then report.
- Never claim a pass. A clean tool run means the tool found nothing. Say what was **not** checked (real TalkBack run, Switch Access, users).
- Separate **confirmed** (reproduced on device or obvious in code) from **suspected**.
- Dismiss system dialogs before dumping. Run `device-toggles reset` at the end.
- `contentDescription = null` is correct for decorative images. Do not report it blindly: decide whether the image carries information.
- Do not fix in the same pass. A report first, so the before state stays on record.

## Severity

`error` = a user cannot complete a task or cannot tell what a control does. `warning` = harder or slower. `info` = check by a human.
