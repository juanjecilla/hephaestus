# Tests that keep a fix fixed

## 1 · Semantics assertions (any Compose test, also Compose Multiplatform `runComposeUiTest`)
```kotlin
@Test fun clearButtonIsLabelledAndBigEnough() = runComposeUiTest {
    setContent { SearchField(query = "dune", onQueryChange = {}) }
    onNodeWithContentDescription("Clear search")
        .assertHasClickAction()
        .assertTouchHeightIsAtLeast(48.dp)
        .assertTouchWidthIsAtLeast(48.dp)
}

@Test fun seasonHeaderIsAnExpandableButton() = runComposeUiTest {
    setContent { SeasonHeader(season = 2, expanded = false, onToggle = {}) }
    onNodeWithText("Season 2").assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
}

@Test fun swipeCardHasActions() = runComposeUiTest {
    setContent { SwipeCard(...) }
    onNodeWithTag("card").assert(SemanticsMatcher.keyIsDefined(SemanticsActions.CustomActions))
}
```
Print the tree when a matcher fails: `onRoot().printToLog("a11y")`.

## 2 · Automatic checks, Android only (Accessibility Test Framework)
Artifact `androidx.compose.ui:ui-test-junit4-accessibility` (Compose 1.8.0+). Checks content labels, contrast, touch target size, traversal order on what the test renders.
```kotlin
@get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

@Test fun searchScreenPassesAccessibilityChecks() {
    rule.setContent { SearchScreen(...) }
    rule.enableAccessibilityChecks()
    rule.onRoot().tryPerformAccessibilityChecks()      // also runs after every performClick()
}
```
Put it in `androidInstrumentedTest` in a KMP project. These checks complement a real TalkBack pass; they do not replace it.

## 3 · Lint
Run Android Lint with accessibility issues as errors in CI (`lint { error += "ContentDescription" … }`) so a missing label breaks the build.

## 4 · Font scale
A screenshot or semantics test with `CompositionLocalProvider(LocalDensity provides Density(density, fontScale = 2f))` around the screen.
