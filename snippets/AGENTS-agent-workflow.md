# Agent workflow rules

Rules for agents that open, fix and merge PRs. Paste the ones that apply
into your `AGENTS.md`. Each one comes from a mistake that cost a review
window, a red CI run, or a wrong statement on a PR.

## Git and shell

- Chain "commit, push, reply" with `&&` only. With `;`, a pre-commit hook
  rejected the commit, the push was a no-op, and the reply cited the old SHA.
- `read -r a b <<<"$(cmd)" || true` swallows `cmd`'s failure. Capture first
  (`x="$(cmd)"`), then parse. Helpers must tell "none" (empty, exit 0) apart
  from "lookup failed" (exit 1).
- zsh does not word-split `$VAR`. `F="a b"; git checkout -- $F` passes one
  path. Use arrays.
- BSD tools on macOS: `sed` has no `\b`, and there is no `timeout`
  (`perl -e 'alarm N; exec @ARGV' cmd …` works).
- A peer session's worktree can hold the branch you need (`git worktree add`
  refuses it). Use `--detach` and `git push origin HEAD:<branch>`, then tell
  the peer its copy is behind.
- Files a git worktree does not get (such as `local.properties`) must be
  copied in for local builds.

## Review hygiene

- When a fix changes behaviour (triggers, branches, gates), grep the docs that
  describe it and update them in the same push. Doc drift costs another
  review.
- When a reviewer finds a second race in the same guard, stop patching cases
  and move where the state is captured. One fix took three rounds, each
  closing one ordering, until the state was snapshotted when the work was
  queued.
- A dependency bump whose changelog says "now throws" or "now rejects" ships
  with its guard in the same PR, not as a follow-up issue.
- A helper that merges state on the caller's behalf must update the caller's
  copy (return it, or replace it in place). Otherwise the next save treats the
  other writer's fields as deliberate deletions.
- Research documents are reviewed like code. Re-derive each "therefore" from
  its sources and recompute every number before publishing.

## Bots and dependency PRs

- Dependabot cannot read Actions secrets. A workflow that runs on its PRs and
  needs a secret needs it set again with `gh secret set NAME --app dependabot`.
- A ruleset that requires one approval blocks `gh pr merge` on a bot PR. Run
  `gh pr review N --approve` first, and never use `--admin`.
- A bump that changes generated files (lockfiles, dependency-verification
  checksums, a license list) fails CI until the files are regenerated on the
  bot's branch. Automate it with a workflow on `dependabot/*`, and wait for the
  bot's own run to finish before pushing so you don't race its commit.
- `actions/setup-node` with a major-only `.nvmrc` uses the runner's cached
  patch, which lags. Set `check-latest: true` when tools enforce patch floors.

## CI and release trains

- Release notes must never gate a release. Generate them from conventional
  commits, and let hand edits survive regeneration.
- Anything that asks "what was the last release" must count versions still in
  flight (release branches, RC tags), not only final tags.
- A promotion gate reading "CI not green" also fires while CI is still running
  after a push. Wait for the checks first.
- Release branches run their own copy of the workflows: a fix on the main
  branch does not reach an open release branch.
- A job that runs every day must be idempotent. Early-return once its step is
  recorded, keep the original date, and do the side effect *before* persisting
  state, so a failed side effect retries and a successful one is not repeated.
- Switching CodeQL from default setup to an advanced workflow: turn default
  setup off first, or every SARIF upload fails.

## Secrets

- Check a private key without printing it. Sign a JWT with
  `openssl dgst -sha256 -sign` and call the API (for a GitHub App, `GET /app`
  returns its slug when the key matches). Afterwards, tell the owner where the
  key file sits and that it should move to a password manager.
