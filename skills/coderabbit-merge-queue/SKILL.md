---
name: coderabbit-merge-queue
description: Merge a backlog of PRs one at a time behind CodeRabbit's rate-limited review gate — a background queue that updates, requests review, waits, and merges only on a clean approval with green CI, stopping on anything else for you to fix and restart. Use when several PRs are waiting on CodeRabbit approval, the user says "queue these PRs", "merge the rest", "run the merge queue", or reviews are rate limited.
---

# CodeRabbit merge queue

CodeRabbit's free OSS plan gives **about one review per hour**, and every push
to an open non-draft PR spends one (its incremental review). Firing review
requests at every open PR gets them all rate-limited for an hour or more.
This skill runs the PRs **in series**, one per review window, in the
background, and hands control back the moment anything needs judgement.

The script is [queue.sh](queue.sh); it is not repo code. [extras/](extras/) has the
long-running variant used for big backlogs: `fullqueue.sh` drives `chain.sh` →
`nextpr.sh` → `fullreview.sh`, and takes one ordered step list (see below).

**Run the scripts from this skill directory, or from a copy under `~/.cache`,
never from `/tmp` or a session scratchpad.** macOS deletes files under
`/private/tmp` that nothing has opened for a few days, and a queue sleeping
through review windows for days lost `nextpr.sh` that way. Do not edit a
script while a queue is running it: bash reads a script as it runs, so an edit
can break the running queue. To change the scripts mid-queue, run the queue
from a frozen copy (`cp extras/*.sh ~/.cache/merge-queue-run/`) and edit here.

## The loop

For each PR, in merge order, `queue.sh`:

1. sleeps one window (`WINDOW`, 3600 s) — skipped for the first PR with
   `NO_FIRST_SLEEP=1` when the last review was over a window ago;
2. stops on a merge conflict; otherwise `gh pr update-branch` so CI runs on
   the merged result;
3. marks the PR ready, and if no review started within `REQUEST_AFTER`
   minutes, comments `@coderabbitai review` (marking ready does not always
   trigger one, and an already-ready PR triggers nothing);
4. waits up to `REVIEW_WAIT` minutes for a CodeRabbit review newer than the
   request, stopping at once on a rate-limit comment;
5. if CodeRabbit re-reviews and finds nothing new it often posts **no review
   at all** (commit status "Review completed", or a reply "Already reviewed
   the last commit"), leaving the old CHANGES_REQUESTED in force — the queue
   then comments `@coderabbitai resolve`, which resolves its threads and
   flips the decision to APPROVED — **only when every root inline comment
   from CodeRabbit has a reply**; otherwise it stops (`… unanswered`), because
   a resolve would approve findings nobody handled (this merged one unfixed);
6. accepts **APPROVED with zero new inline comments** — or COMMENTED when the
   PR's `reviewDecision` is still APPROVED (a re-review with nothing to say);
7. waits for the base branch's **required** checks only (`gh pr checks
   --required`), polling up to `CHECKS_TIMEOUT` (5400 s), stops if any fail or
   are still pending at the deadline, then merges (`MERGE_FLAGS`, default
   `--squash`). An optional check can stay queued forever: GitHub's own
   `.github/dependabot.yml` check did for 39 hours, and an unbounded
   `gh pr checks --watch` over every check stalled the whole queue behind it.

Its output is `merged <pr>` per success, then `queue done`, or one line
`STOP <pr>: <reason>` and exit 1.

## Running it

Before starting:
- **Draft every queued PR that is not up next** (`gh pr ready N --undo`),
  including PRs other sessions or agents opened as ready. A ready PR spends a
  review on *any* push to it, whether yours, another session's, or a
  `gh pr update-branch`. Some PRs are not yet reviewed; others are waiting on
  fixes for a CHANGES_REQUESTED review. Drafting them parks them, so you can
  push fixes, merge the base in, or renumber clashing migrations or ADRs at no
  cost. The queue marks each one ready on its turn. Re-check after every merge
  (`gh pr list --json number,isDraft`): new PRs keep arriving as ready.
- On a STOP, draft the PR **before** pushing the fix, then requeue it.
- Use the parked time to prepare the PRs further down the queue:
  - reply to findings already fixed but never answered;
  - merge the base in;
  - resolve number collisions with PRs ahead in the queue (migration files,
    ADR numbers). The PR merging later renumbers.
- When a PR merges, retarget any PR stacked on its branch
  (`gh pr edit M --base develop`), since CI only runs on PRs into the main
  branches. GitHub often does this by itself when the merged branch is deleted,
  and then `gh pr edit` fails with "A pull request already exists". It does so
  a few seconds after the merge, so a check made right after can still see the
  old base: check `baseRefName` first, and on a failed edit wait and check it
  again (`fullqueue.sh`'s `base:N` step does both).
- A stacked PR whose base was **squash**-merged still carries the base's
  original commits, and merging develop into it conflicts on every file they
  share. Rebuild it: `git checkout --detach origin/develop`, cherry-pick only
  its own commits, then `git push --force-with-lease=<branch>:<old sha>`, and
  say so in a PR comment.
- PRs you or agents open while a queue runs go up as **drafts** and never
  mention `@coderabbitai` — the queue marks them ready on their turn.
- Order: dependencies first (stacked or conflicting PRs after what they build
  on), then cheapest-to-review.

Start it as a background command and get on with other work; you are notified
when it exits:

```bash
Q=<this skill's directory>    # e.g. ~/.claude/skills/coderabbit-merge-queue
"$Q/queue.sh" 263 264 265     # run_in_background: true
```

For a long backlog with stacked PRs, use **one** `extras/fullqueue.sh` process
with the whole ordered list. Do not chain a waiter per added PR: one STOP at
the head makes every waiter cascade to "skipped", and each has to be killed by
hand.

```bash
BASE_BRANCH=develop "$Q/extras/fullqueue.sh" \
  620 624 base:648 593 640 close:631:640 648      # run_in_background: true
```

Steps are `N` (a PR), `base:N` (retarget a stacked PR; a no-op if GitHub
already did it) and `close:N:M` (close N as superseded by M). On a stop it
prints `REMAINING: …`, so the restart is that one line. To add PRs, stop the
queue and rerun it with the longer list: a queue that is only sleeping loses
nothing. `BASE_BRANCH` defaults to the repo's default branch; set it under
git flow, where PRs target `develop` but `main` is the default.

`nextpr.sh` times the window (plus `MARGIN`, 180 s, because CodeRabbit starts
its hour at its own reply, about a minute after the request) from the **last review request**, which it
records in a stamp file (`STAMP`, default `extras/.last-request-<owner_repo>`),
not from the last merge. Before it waits it runs `gh pr update-branch` on the
PR, which is still a draft, so the push spends no review and CI runs during the
wait instead of after the approval. Sleeping a full window after each merge
used to put the previous PR's CI on top of the window: about 35 minutes lost
per PR. A restart after a fix waits only what is left of the window too.

## On `STOP <pr>: <reason>`

Fix the cause, then restart **from that PR** with the rest of the list
(the queue waits out what is left of the window since its last request):

| Reason | Do |
|---|---|
| `review state=CHANGES_REQUESTED inline=N` | Read the root inline comments (`gh api repos/R/pulls/N/comments`, `in_reply_to_id == null`). Verify each against the code — CodeRabbit is sometimes wrong (it once claimed an existing Gradle task did not exist). Fix the valid ones **in one push**; reply to every comment (`…/comments/<id>/replies`) with "Valid — fixed in `<sha>`: …" or why not. File an issue for anything valid but out of scope. |
| `review state=COMMENTED inline=0` | Findings are in the review **body** (look for "Outside diff range" / 🟡 / 🟠). Fix them; nothing to reply to inline. If the body has none and the decision is APPROVED, just merge by hand. |
| `merge conflict with base` | Merge the base into the branch, resolve (usually both sides plus updating to the base's new helpers), run the touched modules' tests, push. |
| `CI failing` | Read `gh run view <id> --log-failed`, grep `e: `/`FAILED`/`What went wrong`. A branch merged with a refactor often breaks on references the refactor removed. |
| `rate limited` / `no review in N min` | A stated wait up to `RATE_RETRY_MAX` (900 s) was already sat out and asked once more, so this means a long wait or a second refusal. Nothing to fix; restart from that PR. If its last fixes are pushed and the decision is still CHANGES_REQUESTED, comment `@coderabbitai resolve` and merge once it reads APPROVED. |
| `review state=CHANGES_REQUESTED inline=N unanswered` | The last review's findings were never answered; resolving would approve them. Handle them exactly as the `CHANGES_REQUESTED` row (fix in one push, reply to every comment), then restart from that PR. |
| `merge refused` | Check branch protection / required checks; never `--admin` around the gate. |
| `required checks still pending after Ns` | Find the stuck check (`gh pr checks N --required`). A runner that never picked the job up: rerun it (`gh run rerun <id>`). A check that waits on an outside service: look at that service. Restart from that PR once it moves. |
| `nextpr.sh missing in <dir>` | The scripts were deleted under the queue (a `/tmp` cleaner). Run them from this skill directory and restart. |

## Lessons

[references/lessons.md](references/lessons.md) records the incident behind each odd-looking rule. Read it before changing the scripts.

## Tests

`extras/test/queue-test.sh` runs every script against a fake `gh`
(`extras/test/fake-gh`) driven by JSON fixtures, with every pause set to zero.
Run it after any change to the scripts:

```bash
"$Q/extras/test/queue-test.sh"   # needs jq
```

The fake answers `--json … -q FILTER` by running FILTER over a fixture with jq.
It returns the k-th fixture on the k-th call, for checks that change while the
queue waits, and records a `--watch` over a pending check as a stall, since the
real one would block. Each stop reason has a case, and so does each incident
the scripts were changed for: a rate-limit reply posted seconds after an
approval of the head, an optional check stuck in "queued", a `nextpr.sh`
deleted under a sleeping queue, GitHub retargeting a stacked PR itself (also
seconds after the check), and the window timed from the last request.

## Known gaps

- `gh pr update-branch` runs with its output discarded, so a branch that
  conflicts with the base only shows up as `merge refused` *after* CodeRabbit
  has spent a review on it. Check `mergeable` again before requesting the
  review. For now, treat `merge refused` on an APPROVED PR as a conflict
  first: merge the base in; when the conflict is docs-only, the approval stands.
- A dated backlog or changelog section that several PRs append to conflicts
  on every merge. Resolve as the union of both sides under one heading.

## Rules

- Never batch review requests, never admin-merge to get round the rate
  limit, never merge without a CodeRabbit approval.
- **CodeRabbit skips PRs authored by bots** (Dependabot, Renovate: "Review
  skipped — authored by a bot without an assigned CodeRabbit review seat"),
  so they never get its approval. Keep them out of the queue. Ask the user
  once per repo whether green dependency bumps may be merged without
  CodeRabbit. If yes, merge each by hand once its CI is green, one at a time,
  re-checking the others after each merge. A red check is usually a real
  incompatibility: fix it on the bot's branch (or close the PR and file an
  issue) rather than merging around it.
- Hold PRs that must not ship yet out of the list entirely (e.g. migrations
  that a merge would auto-deploy to production).
- Report to the user at each stop: what was merged, what stopped and why,
  what you fixed, what is next in the queue.
