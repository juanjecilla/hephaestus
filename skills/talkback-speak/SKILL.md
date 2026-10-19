---
name: talkback-speak
description: Approximate what TalkBack would announce for an Android screen, as plain text, from an adb UiAutomator dump. Use to hear an app's accessibility problems early without a device speaker or TalkBack running, to compare a screen before and after a fix, or to put "what a blind user hears" on a slide or in a bug report.
license: Apache-2.0
---

# talkback-speak

```bash
skills/a11y-audit/scripts/dump_tree.sh out home          # → out/home.xml
python3 skills/talkback-speak/scripts/speak.py out/home.xml
```

```
  1  Search movies & TV, edit box, double tap to activate
  2  Welcome to Muviss
  6  Got it, button, double tap to activate
 16  «unlabeled», button, double tap to activate        ← a blind user hears this
```

Reading order is the order of the nodes a screen reader can focus. A clickable container is merged into one announcement, as TalkBack does. Unlabeled clickable nodes print as `«unlabeled»`.

## Honest limits (say them out loud in a talk)

It is an approximation. UiAutomator does not expose headings, roles set with `Modifier.semantics`, state descriptions, custom actions or the real traversal order. Real TalkBack output is the source of truth: record it with `device-toggles` (`talkback on`, `record`) before quoting it.

## Use

- Diff two runs (before/after a fix): `diff <(speak.py before.xml) <(speak.py after.xml)`.
- Feed the output to the model with the screenshot and ask: "what would a blind user not understand here?"
- `--all` also lists non-text nodes with descriptions.
