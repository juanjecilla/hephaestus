# Bot pushes from CI: tokens and trust

Learned on muviss #497, a workflow that regenerates `gradle/verification-metadata.xml` on three hosts and pushes it back to the PR branch. The same shape fits any bot-regenerated lockfile.

## A GitHub App token lives one hour

`actions/create-github-app-token` mints an installation token that expires after an hour. A job that mints it at the start and pushes after a two-hour build fails with `gh: Bad credentials (HTTP 401)` and loses its output. `actions/checkout` also persists the token it was given, outside the local `http.<url>.extraheader` key in v7, so unsetting that key does not stop the expired token being sent. Mint the push token right before the push, and check out with `persist-credentials: false`.

## Keep the token out of the job that runs the build

A build runs code chosen by its dependencies and plugins. If that job later pushes with a token, the build can plant a `pre-push` hook that receives it. Split by secrets:

- **Build jobs:** no secrets, `contents: read`, `persist-credentials: false`; hand the generated file on as an artifact (a reusable `workflow_call` workflow per host keeps the order explicit).
- **Push job:** a fresh runner that runs no repository code. Mint the token with `permission-contents: write` only, download the artifact outside the workspace, accept only the expected file, commit with `core.hooksPath=/dev/null`, push without force to the commit the build jobs checked out.

## Accept only additions

The build that wrote the file could also have written a policy that trusts everything. Before copying the artifact in, compare it with the checked-out file: the policy block byte-equal (canonicalised), every existing entry unchanged, and new entries shaped exactly as the tool writes them. Test the guard by extracting the step's own `run:` text from the YAML and running it against tampered fixtures.

## Gate the triggers

- A manual dispatch only on feature branches and never on a tag (`github.ref_type == 'branch'`): a bot that can bypass rulesets must not push to protected branches, and a tag's name would become a new branch.
- Bot PRs: the author **and** the actor must be the bot, and the head must be this repository. The actor check stops the bot's own push from re-triggering the workflow and is what grants Dependabot secrets; a maintainer who reopens such a PR re-runs it by dispatch.
- A repository check that pins runner images must follow `${{ inputs.os }}` to the values callers pass, the way it follows `${{ matrix.os }}`.
