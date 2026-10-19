# Compose accessibility patterns

Each: the problem, the fix, why.

## Images and icons
```kotlin
// informative
Icon(Icons.Default.Search, contentDescription = stringResource(R.string.search))
// decorative: next to text that says the same
Icon(Icons.Default.Check, contentDescription = null)
```

## A row that is one control
```kotlin
Row(Modifier.clickable(onClickLabel = stringResource(R.string.open_settings), role = Role.Button, onClick = onOpen)) {
    Icon(icon, contentDescription = null)   // merged into the row: not announced twice
    Text(title)
}
```
`clickable` merges descendants. For non-clickable groups use `Modifier.semantics(mergeDescendants = true) {}`.

## Touch targets (48 × 48 dp)
```kotlin
// wrong: the container is forced to 24 dp, so is the target
IconButton(onClick = onClear, modifier = Modifier.size(24.dp)) { Icon(...) }
// right: size the icon, keep the button's 48 dp
IconButton(onClick = onClear) { Icon(..., modifier = Modifier.size(24.dp)) }
// custom clickable: Modifier.minimumInteractiveComponentSize() before .clickable
```

## Headings
```kotlin
Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
```

## State and role
```kotlin
Modifier.selectable(selected = isSelected, role = Role.Tab, onClick = onSelect)   // announces "selected"
Modifier.semantics { stateDescription = if (done) "Watched" else "Not watched" }
Modifier.toggleable(value = on, role = Role.Switch, onValueChange = onToggle)
```

## Gestures need an alternative (swipe, drag, tap-on-half)
```kotlin
Modifier.semantics {
    customActions = listOf(
        CustomAccessibilityAction(saveLabel) { onSave(); true },
        CustomAccessibilityAction(skipLabel) { onSkip(); true },
    )
}
// and a visible button for anyone who cannot swipe
```
For a value picked by tapping (a rating): expose it as adjustable (`progressBarRangeInfo` + `setProgress`) so users can increase/decrease.

## Text that scales
- Text in `sp`, never `dp`. No fixed `height` on text containers: `heightIn(min = …)`.
- Do not truncate meaning (`maxLines = 1`) on labels users need; allow wrapping.
- Adapt the layout, not only the size: `if (LocalDensity.current.fontScale > 1.5f)` switch a grid to a list.
- Test at `font-scale 2.0` (device-toggles).

## Reading order and grouping
`Modifier.semantics { isTraversalGroup = true }` and `traversalIndex = n` when visual order differs from reading order.

## Announcing changes
`Modifier.semantics { liveRegion = LiveRegionMode.Polite }` on a status line that updates (loading, saved, error). Not on things that change every second.

## Motion
There is no Compose API for reduce-motion. Read `Settings.Global.ANIMATOR_DURATION_SCALE`; at `0f` skip decorative animation.

## Colour
Text 4.5:1 (3:1 large), icons and borders 3:1, in light and dark. Never colour alone for meaning (add an icon or text). Text over images: give it an opaque scrim. Check with `contrast-check`.
