# Lessons behind the queue

Each entry is an incident from running this queue over a month-long backlog
of ~100 PRs, and what changed because of it. Read it before changing the
scripts: most odd-looking lines exist for one of these.

## CodeRabbit's review states

- **Filter by author.** Only reviews by `coderabbitai` count. A COMMENTED
  "review" can be a thread reply (yours or its own), not a full review.
- **A re-review with nothing new posts no review.** It says "Full review
  finished", "Already reviewed the last commit", or only sets its commit
  status to "Review completed". The old CHANGES_REQUESTED stays in force.
  `@coderabbitai resolve` flips the decision to APPROVED. Any custom waiter
  must handle this, not only `queue.sh`.
- **Resolve only answered findings.** A resolve approves every open
  thread. The queue refuses (`… unanswered`) unless every root inline comment
  has a reply. This once merged a finding nobody had fixed.
- **Rate-limit replies can follow an approval.** One approval landed at
  00:34:09 and the limit reply at 00:34:22. Check for a new review *before*
  the rate-limit comment, and accept the latest review if it approved the
  head commit.
- **Rate-limit replies state the wait** ("next included review will be
  available in 47 minutes"). Sleep that long plus a margin rather than a blind
  window.
- **Thread replies spend the budget too.** Each reply to a finding draws a
  COMMENTED response. If CodeRabbit accepts your answer in the thread,
  `@coderabbitai resolve` approves without spending a new review.
- **Decline with evidence, then resolve.** When a finding is wrong, reply with
  the reason (for example "the other 34 tests in this file use this form; the
  real constraint is X") and comment `@coderabbitai resolve`. No push, no
  review spent. Only state CI facts you have checked: "the iOS job is green"
  while it was still pending had to be corrected.
- **Point to the stacked PR that fixes it.** If a later PR in the stack
  already fixes a finding, say so in the reply and resolve.
- **Read the review body even when approved.** "Outside diff range" findings
  live there and were real (an alpha channel that App Store Connect rejects).
- **CodeRabbit skips bot-authored PRs** (Dependabot, Renovate, a GitHub App
  of your own). Resolve on a person-authored mirror PR, or merge bot bumps by
  hand under a rule the owner agreed to.
- **`.coderabbit.yaml` `base_branches`** must include `release/.*` and
  `hotfix/.*`, or fix PRs into release branches get no automatic review.

## Waiting on CI

- **Wait on required checks only, with a deadline.** `gh pr checks --watch`
  waits on every check. GitHub's own `.github/dependabot.yml` check stayed
  QUEUED for 39 hours and the queue sat behind it. Poll
  `gh pr checks --required` up to `CHECKS_TIMEOUT` and stop with a reason.
- **A job cancelled at its timeout with zero steps run** means the runner
  never attached. It is an infra flake, not code: `gh run rerun <id>
  --failed`. An approval given before the flake stands.
- **A guard test merged after a branch was opened can catch that branch.**
  After merging the base in, run the tests the base brought in
  (`git diff --name-only HEAD@{1} HEAD -- '*test*'`), not only the branch's own.

- **Check CI before asking for the review, not only before the merge.** A
  golden that a rebuilt PR never re-recorded failed on every push, and the
  queue still asked for, and fixed, three more reviews before stopping on CI
  after the approval. The checks run during the window wait, so look at them
  when it ends.

## Stacks, drafts and order

- **A push to a ready PR spends a review**, including `gh pr update-branch`
  and other sessions' pushes. Draft every queued PR that is not up next. The
  queue marks it ready on its turn.
- **GitHub retargets stacked PRs by itself** when the merged branch is
  deleted. A later `gh pr edit --base` then fails with "A pull request already
  exists". Make the retarget idempotent: check `baseRefName` first. GitHub does
  it a few seconds after the merge, so the check can still see the old base
  and the edit then collides: on a failed edit, wait and read the base again.
- **Rebuild a stacked PR after a squash merge; don't merge it.** It still
  carries the base's original commits, so merging the base conflicts on every
  shared file (11 files in one case, 0 after a rebuild). Check out the base
  detached, cherry-pick only this PR's own commits, then
  `push --force-with-lease=<branch>:<old sha>` and comment that it was rebuilt.
- **Parallel agents all take "the next" migration or ADR number.** Four
  drafts each added the same migration. Assign numbers at merge time. Queue
  numbered PRs last, stack them, and renumber each on its turn.
- **A stacked PR may skip a check** that only runs on PRs into the main
  branch (for example a landing-page guard). Expect it to go red once
  retargeted.

## Running the queue

- **Time the window from the last review request, not from the last merge.**
  A fixed hour of sleep after each merge put the previous PR's CI on top of
  it: #693 merged at 06:14, the next PR was asked at 07:14, approved at 07:23,
  and only then started 35 minutes of CI from its `update-branch`. Update the
  next PR's branch *before* the wait (it is still a draft, so it costs no
  review) and sleep only what is left since the recorded request.
- **CodeRabbit's hour starts at its reply, not at your request.** Timed to the
  second from the request, the next one was refused "available in 37
  seconds". Add a margin to the window, and when a rate-limit reply states a
  short wait, sit it out and ask once more instead of stopping the queue.

- **One process with the whole ordered list.** A ladder of waiters, each
  watching the previous one's output, cascades into "skipped" on any STOP and
  has to be killed by hand. `fullqueue.sh` prints `REMAINING: …` on a stop, so
  the restart is one line. To add PRs, stop it and rerun with the longer list.
- **Never run the queue from `/tmp` or a scratchpad.** macOS deleted
  `nextpr.sh` under a queue that was sleeping through review windows. Worktrees
  there lose their `.git` file the same way.
- **Never edit a script a queue is running.** Bash reads it as it goes. Run
  from your own frozen copy in `~/.cache/merge-queue-run/<repo>-<timestamp>/`
  (see SKILL.md) and edit the original. A shared flat copy was overwritten by
  another session's run.
- **Use the agent's background-task feature, not `&`.** A detached `&` gives
  no completion notification.
- **One queue per repo.** Before starting, check for another session's queue
  (`pgrep -fl queue.sh`).
- **Hand-offs between waiters break.** `queue.sh` insists on a review newer
  than its own request, so handing it an already-approved PR timed out after
  90 minutes. A waiter that sees APPROVED must check CI and merge itself, and
  must STOP at once with the real state otherwise.

## Check the PR still merges before spending its review

`gh pr update-branch` fails quietly on a conflict, so a PR whose base moved under it (the PR merged ahead of it touched the same lines) was reviewed, approved, and then refused at `gh pr merge` — twice in one day (#684, #558), an hour each. `nextpr.sh` now reads `mergeable` after the update (polling while GitHub reports `UNKNOWN`) and stops with `merge conflict with base (no review spent)`; `fullreview.sh` names the conflict when a merge is refused anyway.

## An approval is not final until the merge

Replying to CodeRabbit's comments can resolve its threads and earn an empty APPROVED (#563, 14:08). The full review it was still running landed eleven minutes later as CHANGES_REQUESTED, after the queue had taken the approval and started waiting for CI. Branch protection refused the merge, so nothing wrong landed, but the STOP said `merge refused`. `fullreview.sh` now reads `reviewDecision` again after the CI wait and stops with the real state.

## Stacks whose base was squash-merged

A PR stacked on a branch that later squash-merged still carries that branch's original commits, so merging the base in produces dozens of add/add conflicts (#665: 35). Rebuild instead: `git log origin/<base>..<branch>` names the PR's own commits; check out the base detached, cherry-pick only those (`git checkout --conflict=diff3 <file>` shows the common ancestor while resolving), force-push with a lease, and redo every PR stacked on top the same way. The queue's `base:N` step only retargets; the rebuild is yours.

## After every merge, check the rest of the queue

The PR that just merged can make any later one conflict. `nextpr.sh` stops such a PR before spending its review, but you only find out when its turn comes, an hour later. Right after each merge, read `mergeable` for every queued PR (poll while it says `UNKNOWN`) and fix the conflicts while they wait.

## When pushes fail, check GitHub before your keys

`Permission denied (publickey)` over SSH and `Internal Server Error` over HTTPS at the same time was a GitHub incident, not a key problem: `curl -s https://www.githubstatus.com/api/v2/summary.json`. Pushing without touching git config: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push https://github.com/O/R.git HEAD:refs/heads/B`, in a retry loop. Reply "fixed in <sha>" only after the push has landed; a reply naming a commit that is not on GitHub misleads the reviewer.

## A required job "cancelled" with no steps

A runner that never arrived (macOS capacity during an Actions incident) shows as a required check `cancelled` with zero steps, and `nextpr.sh` stops on it as failing CI. `gh run rerun <id> --failed`, then chain the queue behind the rerun. Confirm the rerun registered (the bucket reads `pending`) before a waiter polls it, or it reads the old failure and moves on.

## Chains in background shells

Background commands may run in zsh, where an unquoted `$list` does not split into words: `fullqueue.sh $ok` passed `" 497"` as one PR number. Use an array, `${=ok}` in zsh, or a loop that quotes each number.

## Push back with a measurement

A finding that asks for "strict by default" can be wrong for reasons only a run shows. #497's reviewer asked to rethrow on any resolution failure; a run showed 663 configurations fail that call on every host, so strict would have broken every job. Measure first, then either fix or reply with the number and what does guarantee the property. If the same point comes back, stop and ask the owner rather than loop.

## A long queue filled the main session

Every `STOP` cost a read-fix-reply-restart cycle in the one session that also owned the queue, so unrelated PRs piled up in a single transcript. There is no tool for an agent to `/compact` itself. The orchestrator now stays thin and a fixer subagent (own context, cheap model, worktree) does each fix and returns a seven-line report; a stack keeps one fixer so the feature stays in its head, and a repeat failure upgrades the stack to an Opus fixer. Stack membership is read once at queue start (`extras/stacks.sh`), because merging a base retargets its child onto develop and erases the link.


## `nohup … &` hides the STOP

A queue started as `nohup fullqueue.sh … &` inside a background command makes the *wrapper* exit in a second; the harness notifies "completed" for that, and nothing when the queue stops. The STOP on PR #747 (red `build` before review) waited about five hours until the user noticed nothing was running. Start `fullqueue.sh` directly with `run_in_background: true` so its exit is the notification. A start from the wrong directory fails with "not a git repository" for the same reason: `cd` to the repo in the same command.

A second Muviss queue did the same thing on 2026-11-20 (restart after a fix, `nohup … & disown`; the stop on #1005's merge conflict waited about five hours), even with the lesson above in this file: a rule in prose is not enough. `fullqueue.sh` now refuses an untracked start (`QUEUE_TRACKED=1`), records `last-exit` at start and exit, notifies on every stop, and `status.sh` reads the record (DIED when it says running and the pid is gone). Tests: `extras/test/queue-test.sh`, "fullqueue.sh exit record" and "status.sh".

## A dead network reads as an answer

`gh` prints nothing when the network is down, and the scripts took nothing for an answer: #936 was reported "rate limited" (the rate-limit comment count came back empty, and empty is not `0`) and #925 "no full review in 60 polls" (the request was never posted, because `gh pr comment` failing was not checked), both while the Mac's network dropped. Now `nextpr.sh` stops at once with "could not ask for the review" / "could not mark it ready" and records no request, and `fullreview.sh` does not count a failed read as a poll: it asks again and stops with "GitHub unreachable" only after `NET_FAIL_MAX` (30) failed reads. Tests: "GitHub unreachable" in `extras/test/queue-test.sh`; `fake-gh` gained `flaky-view-N`.

