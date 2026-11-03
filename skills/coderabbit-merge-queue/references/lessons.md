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
  from a frozen copy in `~/.cache/merge-queue-run/` and edit the original.
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
