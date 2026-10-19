## Accessibility (Android / Compose)

These rules apply to every UI change. Copy this block into your `AGENTS.md` or `CLAUDE.md`.

- Every `Image`/`Icon`/`AsyncImage` that carries information has a localised `contentDescription`; decorative ones use `null`. Never repeat text that is already visible next to it.
- Every clickable has a 48 × 48 dp target (size the icon inside `IconButton`, never the button), a `role` and, when the label is not obvious, an `onClickLabel`.
- Group a row that is one control (`clickable` merges; otherwise `semantics(mergeDescendants = true)`).
- Titles use `semantics { heading() }`. Selected/checked/expanded state is announced (`selectable`, `toggleable`, `stateDescription`).
- A swipe, drag or tap-on-half has an accessible alternative: `customActions` and a visible button.
- Text in `sp`, no fixed heights on text, layouts survive `font scale 2.0` (switch grid → list, do not clip).
- Text 4.5:1 (large 3:1), icons and borders 3:1, in light and dark; never colour alone. Text over images gets an opaque scrim.
- Add a test with each fix: semantics assertions in common tests, `enableAccessibilityChecks()` in instrumented tests.
- Before saying "accessible", say what you did not check: a real TalkBack pass, Switch Access, real users.
