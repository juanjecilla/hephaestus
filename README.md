# hephestus

Skills and tools to build with AI agents. The first module is **Android accessibility**: audit an app, fix what you find, test it so it stays fixed, and hear what a screen reader hears.

> Hephaestus, the Greek god of the forge, was lame, and built his own assistive technology: golden maidens who helped him walk (Iliad 18). Build what you need.

Built for the talk *a11y on Android? AI makes it easy* (DevFest Jerez 2026). Works with Claude Code, and with any agent that reads `SKILL.md` files.

## Skills

| Skill | Does | Needs |
|---|---|---|
| [`a11y-audit`](skills/a11y-audit) | static scan of Compose sources + tree audit of a running screen, report per person | python3, adb |
| [`a11y-fix`](skills/a11y-fix) | idiomatic fixes + tests (semantics assertions, ATF) | your code |
| [`device-toggles`](skills/device-toggles) | TalkBack, font scale, display size, animations, contrast, colour filters, screenshots, recordings, reset | adb |
| [`talkback-speak`](skills/talkback-speak) | approximates what TalkBack says, as text | python3 |
| [`contrast-check`](skills/contrast-check) | WCAG contrast of a pair, of Material colour schemes, of hard-coded colours | python3 |

Also: [`snippets/AGENTS-a11y.md`](snippets/AGENTS-a11y.md) (rules to paste into your `AGENTS.md`) and [`snippets/gemini-prompts.md`](snippets/gemini-prompts.md) (the same workflow for Gemini in Android Studio).

## Install

Claude Code:
```
/plugin marketplace add juanjecilla/hephestus
/plugin install hephestus
```
Other agents: copy `skills/<name>` into the folder your agent reads (`.agents/skills/`, `~/.claude/skills/`…). Each skill is self-contained except `a11y-audit`, which also calls `talkback-speak`.

## Try it in two minutes

```bash
adb devices                                         # an emulator or test device, not someone's phone
skills/a11y-audit/scripts/dump_tree.sh out home
python3 skills/a11y-audit/scripts/tree_audit.py out/home.xml --density $(cat out/home.density)
python3 skills/talkback-speak/scripts/speak.py out/home.xml
python3 skills/a11y-audit/scripts/scan_compose.py path/to/your/ui/module
```
Then ask your agent: *"Use the a11y-audit skill on this app, then a11y-fix on the errors."*

## Honest limits

The scripts are heuristics. They find missing labels, small targets, gesture-only controls and bad text sizes. They cannot judge whether a label is **good**, whether the reading order makes sense, or whether a person can finish a task. A clean run is not a pass: test with TalkBack and with people who use it.

## Roadmap

`content-description-gen` (vision-model descriptions for static drawables), `a11y-pr-review` (accessibility review of a diff in CI), and more AI tooling beyond accessibility.

## License

Apache-2.0.
