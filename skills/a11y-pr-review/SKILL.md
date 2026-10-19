---
name: a11y-pr-review
description: Review an Android Compose pull request or branch for accessibility regressions, looking only at what the diff adds - new images without a decision about contentDescription, clickables without role or label, gestures without alternatives, text in dp, new colours, and missing tests. Use for "review this PR for a11y", in CI as a gate, or before merging UI changes.
license: Apache-2.0
---

# a11y-pr-review

Look only at what the change adds. Pre-existing problems belong in an audit (`a11y-audit`), not in someone's PR.

```bash
skills/a11y-pr-review/scripts/scan_diff.sh origin/main      # findings on added lines only; exit 1 on errors
```

## Review checklist (the model does this part)

For each added or changed composable:

1. **Images and icons**: informative → localised `contentDescription`; decorative → `null`, *and the surrounding control still has a label*.
2. **Clickables**: role, `onClickLabel` if the text is not enough, one merged announcement (no icon + text announced twice).
3. **Gestures** (`pointerInput`, swipe, drag, tap-on-half): is there an accessible alternative for everyone?
4. **Text**: `sp`, no fixed heights, survives `font scale 2.0`.
5. **Colour**: new colours checked (`contrast-check`), light and dark, never colour alone.
6. **Strings**: every new user-visible string exists in every supported language.
7. **Tests**: a semantics test (role, label, touch bounds) or an ATF check for what changed.

## Output

A short list: `file:line · what a user experiences · suggested change`. Separate **blocking** (a user cannot tell what a control does) from **suggestion**. Say what you did not check (real TalkBack, Switch Access).

## Do not

- Report the scanner's `small-target` hits as bugs without measuring: Compose expands touch bounds to 48 dp (`a11y-fix`, `references/patterns.md`).
- Report `contentDescription = null` inside a labelled row.
- Approve on a clean scan. "No findings" is not "accessible".

## CI

`scan_diff.sh` exits 1 on errors only. Run it as a non-blocking comment first; make it blocking once the team trusts it.
