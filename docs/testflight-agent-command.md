# Remote TestFlight requests and receipts

Xcode Cloud owns testing, signing, archiving and internal distribution. The small
GitHub job in .github/workflows/testflight-delivery.yml only requests an approved
main build or observes the candidate already triggered by a main merge, then
verifies Apple processing and actual Amit Internal availability.

This is a project delivery adapter, not another coding agent or task dispatcher.
The existing hourly routine still owns Notion pickup and reconciliation. No new
Notion states or duplicate work records are introduced.

## Activation boundary

Prepared code does not mean the adapter is active. It needs an approved merge to
main, the existing internal Xcode Cloud workflow enabled, and Apple API access in
the GitHub environment tyri-internal-delivery. The environment must permit only
the main branch; main retains required PR checks and human merge approval.

The proposed credential destination is that environment in amitsankaran1/Tyri:
ASC_PRIVATE_KEY is an environment secret; ASC_KEY_ID and ASC_ISSUER_ID are
environment variables. Use the existing approved Tyri automation Developer key,
not another key. Copying it off the Mac requires Amit's explicit approval first.
Apple's team key is account-wide; repository/environment restrictions do not
change that Apple scope. Do not put it in Git, Notion, prompts, logs or PR jobs.

The job runs only trusted main code. Its manual/comment request author is fixed
to amitsankaran1. It accepts neither arbitrary source branches nor script text.
The reviewer role remains separate and unassigned; this adapter does not approve
or merge application changes.

## Agent instructions

1. Read the task, current main revision and project authority. Finish the required
   implementation/review/merge path first, or confirm this is a build-only request
   for approved current main. Use Deliver only when delivery is actually accepted.
2. Reconcile the task's existing request comment, GitHub run and Apple run receipt.
   For an app-changing main merge, the receipt job observes Xcode Cloud's automatic
   candidate; it does not start a duplicate build.
3. For an explicitly requested fresh build, post exactly this command on existing
   workflow PR #25 after activation and authority for this command is recorded:

       /tyri-build <task UUID without dashes> <exact 40-hex current-main SHA>

   Use the GitHub connection as amitsankaran1. The accepted comment ID identifies
   the request. Save its URL/ID in the same Notion task. If posting is uncertain,
   fetch existing comments and reconcile before posting again. A status poll is
   not a new build request. Editing a comment does not trigger another build.
4. Read the bot receipt on PR #25, identified by its tyri-delivery marker and the
   original request comment ID. It records the Apple run before waiting and is
   updated after successful processing/group availability. Inspect GitHub job
   failures when it is incomplete. Rerun the same failed job to resume a recorded
   run; never make a new request just because processing is slow.
5. Copy the verified source SHA, Apple run, version/build, processing and Amit
   Internal availability evidence into the task. A green archive or submitted
   upload alone is not delivery. Required device acceptance goes to Human review;
   Done follows the task's agreed outcome.

If the trigger's result is uncertain and no unique Apple run can be established,
the adapter stops rather than risking another upload. A human must reconcile
that concrete ambiguity. An explicit new fresh request can then be authorized.

The control thread and receipt live in the public Tyri repository. Commands carry
only an opaque task ID and public commit SHA; keep personal reports, screenshots
and task text in Notion. No external tester submission/invitation or App Store
release is performed. The job only reads the existing internal-group membership;
it does not change audiences.

## CLI and verification

The same owner can dispatch the workflow with a fresh 32-hex request_id and exact
current main source_sha through GitHub's workflow_dispatch API. This is useful
for setup; the connected agents can use the comment route without a local CLI.

Tests/TestFlightBridgeQA/run.py checks caller/source restrictions, existing-run
reuse, uncertain-write behavior, source/app/group evidence and JWT signatures.
These tests do not establish live job activation. Verify a real main merge and a
separate explicit fresh request after activation, then record their receipts in
the CI task before declaring the remote loop ready.
