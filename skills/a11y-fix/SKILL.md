---
name: a11y-fix
description: Fix accessibility problems in Android Jetpack Compose / Compose Multiplatform code with the idiomatic semantics APIs, and add tests so they do not come back. Use after an a11y-audit report, when asked to make a screen accessible, label images and icons, enlarge touch targets, add headings, roles, state descriptions or custom actions for swipe gestures, or when adding accessibility checks to tests and CI.
license: Apache-2.0
---

# a11y-fix

Input: an `a11y-audit` report (or a screen). Output: the smallest correct change per finding, plus a test.

## Loop

1. Take one finding. Read the surrounding code and the design intent.
2. Apply the matching pattern from `references/patterns.md` (labels, roles, targets, headings, state, custom actions, text scaling, traversal, live regions).
3. Add or extend a test from `references/tests.md` that fails before and passes after.
4. Re-run the same audit step that found it. Show the before/after evidence.
5. One commit per finding or per small group. Say which person it helps.

## Rules

- **Prefer fixing the shared component** (design system) over each call site.
- **Do not add `contentDescription` text that repeats visible text** next to it. Merge the row instead (`Modifier.semantics(mergeDescendants = true)` or `clickable`, which merges).
- **A label says what it is or does, not its type.** "Search", not "Search button".
- **Decorative images get `contentDescription = null`.** Do not invent descriptions to silence a tool.
- **Do not detect TalkBack to change behaviour.** Give every gesture an accessible alternative for everyone; use service detection only for presentation.
- Localise every string you add (`stringResource`, string resources in every supported language).
- Generated image descriptions (a model) are suggestions: a human reads them before they ship.
- Passing the checks is not the finish line: say what you did not verify.

## Done means

The audit finding no longer reproduces, a test guards it, the screen was re-checked at font scale 2.0, and the change was read once as a screen reader would read it (`talkback-speak`).
