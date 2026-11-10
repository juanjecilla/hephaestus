# hephaestus

Skills and tools to build with AI agents. Two modules so far:

- **Android accessibility**: audit an app, fix what you find, test it so it stays fixed, and hear what a screen reader hears.
- **Agent workflow**: merge a backlog of agent-written PRs behind a rate-limited AI reviewer, one at a time, and stop the moment something needs judgement.

> Hephaestus, the Greek god of the forge, was lame, and built his own assistive technology: golden maidens who helped him walk (Iliad 18). Build what you need.

Built for the talk *a11y on Android? AI makes it easy* (DevFest Jerez 2026). Works with Claude Code, and with any agent that reads `SKILL.md` files.

## Skills

### Android accessibility

| Skill | Does | Needs |
|---|---|---|
| [`a11y-audit`](skills/a11y-audit) | static scan of Compose sources + tree audit of a running screen, report per person | python3, adb |
| [`a11y-pr-review`](skills/a11y-pr-review) | accessibility review of a diff, scanner on added lines only, usable in CI | git, python3 |
| [`content-description-gen`](skills/content-description-gen) | proposes localised descriptions for static images, for review | a vision-capable model |
| [`a11y-fix`](skills/a11y-fix) | idiomatic fixes + tests (semantics assertions, ATF) | your code |
| [`device-toggles`](skills/device-toggles) | TalkBack, font scale, display size, animations, contrast, colour filters, screenshots, recordings, reset | adb |
| [`talkback-speak`](skills/talkback-speak) | approximates what TalkBack says, as text | python3 |
| [`contrast-check`](skills/contrast-check) | WCAG contrast of a pair, of Material colour schemes, of hard-coded colours | python3 |

### Agent workflow

| Skill | Does | Needs |
|---|---|---|
| [`coderabbit-merge-queue`](skills/coderabbit-merge-queue) | background queue: one PR per CodeRabbit review window, merges only on approval + green required checks, `STOP <pr>: <reason>` otherwise; the session stays a thin orchestrator and a cheap fixer subagent (one per stack) handles each stop; tested against a fake `gh` | bash, gh, jq |

[`references/lessons.md`](skills/coderabbit-merge-queue/references/lessons.md) lists the incidents behind each script rule.

Also: [`snippets/AGENTS-agent-workflow.md`](snippets/AGENTS-agent-workflow.md) (git, review, bot-PR and release-train rules for agents, to paste into your `AGENTS.md`), [`snippets/AGENTS-a11y.md`](snippets/AGENTS-a11y.md) (rules to paste into your `AGENTS.md`) and [`snippets/gemini-prompts.md`](snippets/gemini-prompts.md) (the same workflow for Gemini in Android Studio).

## Install

Claude Code:
```
/plugin marketplace add juanjecilla/hephaestus
/plugin install hephaestus --marketplace juanjecilla/hephaestus
```
*Install lines are untested against GitHub until the repo is public; `claude plugin validate .` passes.*

The merge queue's orchestrator delegates fixes to two subagents; install them once with `cp skills/coderabbit-merge-queue/agents/*.md ~/.claude/agents/` (a plugin install does not register agents that live inside a skill folder).

Other agents: copy `skills/<name>` into the folder your agent reads (`.agents/skills/`, `~/.claude/skills/`…). Each skill is self-contained except `a11y-audit`, which also calls `talkback-speak`.

Test the merge queue scripts after changing them: `skills/coderabbit-merge-queue/extras/test/queue-test.sh`.

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

More agent-workflow tooling (a release-notes generator from conventional commits, Dependabot regeneration workflows). Next in a11y: a `webview-audit`, Switch Access and Voice Access recipes, and Gemini in Android Studio prompt packs per skill.

## License

Apache-2.0.
