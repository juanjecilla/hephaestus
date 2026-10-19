# Prompts for Gemini in Android Studio (Agent mode)

Paste into Gemini in Android Studio. They match the `hephaestus` skills, for people who prefer the IDE to a CLI. Gemini does not read `SKILL.md` files: the prompt carries the rules.

## Audit one screen (no edits)
> Audit `SearchScreen.kt` and the composables it calls for accessibility. Do not change any code. For each finding give: file:line, what a TalkBack user experiences, and the fix. Check: missing or duplicated contentDescription, touch targets under 48dp (an IconButton with Modifier.size is a bug), clickables without role or onClickLabel, gestures with no alternative, text in dp, hard-coded colours. Group the findings by person: blind, low vision, cognitive, motor. Say what you could not check.

## Fix one finding with a test
> Fix finding 3 only. Use the idiomatic Compose semantics API, change the shared component if there is one, add a Compose test that fails before and passes after (assertTouchHeightIsAtLeast, assertHasClickAction, role assertions), and do not touch anything else.

## Check a diff
> Review the current diff for accessibility regressions only: new images without a decision about contentDescription, new clickables smaller than 48dp, new gestures without alternatives, text sizes in dp, new colours without a contrast check.
