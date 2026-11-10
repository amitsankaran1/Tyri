# Agent work and delivery

Canonical shared policy: [Agent Operating Guide](https://app.notion.com/p/3ee16e0e0e3a814d9fbbe386b62fad21).
Reusable workflow: [ask-matt in Notion Skills](https://app.notion.com/p/9b34cc3b74c0496b82499bc013c9c135).
Tyri profile and current readiness: [Tyri project](https://app.notion.com/p/2e616e0e0e3a80148841ff8ca2cb3647).

## Start work

Forward a bug screenshot, idea, draft, research question or delivery request through any filing agent. It preserves the original report and attachments, checks duplicates and saves one Tasks record with the related project and Status = Inbox. No second coding-chat handoff is needed for work supported by the designated routine and project permissions.

The existing native routine, Advance agent tasks, checks hourly. It reconciles existing attempts before fresh pickup, assesses new requests across projects, and advances work where authorization, tools and coordination are established. Other projects need a usable profile and claim/execution path; shared instructions alone do not provision those capabilities. Historical backlog, parked work, explicit pauses and other executors are preserved.

## Phases and agent instructions

| Status | Agent responsibility | Completion evidence |
| --- | --- | --- |
| Inbox | Capture faithfully; check duplicate/project/existing work. | Original request and evidence. |
| Investigate | Claim a useful next step; research facts and establish scope/outcome. | Findings, assumptions, acceptance checks and next action. |
| Implement | Produce the scoped artifact in checked slices. | Artifact/PR, source revision, meaningful checks and limitations. |
| Agent review | A different agent challenges standards and fulfillment of the original request. | Reviewer, reviewed revision and disposition of material findings. |
| Deliver | Perform authorized delivery; reconcile attempts and verify availability. | Source/artifact identity, receipt, destination and acceptance. |
| Human review | Ask Amit the exact question/approval/acceptance, with a recommendation. | Recorded answer and action/phase to resume. |
| Blocked | Identify the external dependency preventing progress. | Concrete remedy and resumable checkpoint. |
| Done | Verify all agreed criteria, including requested delivery. | Short result and evidence links. |

Future is parked; Archived is retired. The former Design and In progress options are replaced. Phases may be skipped or revisited. Status is a handoff, not permission or an atomic lock; no second phase field or CI/retry statuses.

Use the existing Notion skills: triage and enrich-bug-task for intake, diagnosing-bugs/research for facts, grill-me/prototype for consequential intent/design, implement/tdd for production, and code-review for independent standards/spec review. Delivery uses the project runbook. Do not create a second skills framework.

Keep questions, recommendations and answers in the same task. An agent receiving Amit's answer in another chat saves it before resuming. Research retrievable facts first; continue independent useful work while optional questions are pending. Preserve accepted decisions.

Record the accepted executor, run/session if available, checkpoint time, exact artifact/revision and next action. Use the project's supported claim mechanism before automatic mutating execution; reread after acquisition and reconcile uncertain writes/launches by existing identity before retrying. A proposed reviewer is not an accepted handoff. GB may own review/check coordination later; no reviewer is installed by this document.

For code PRs the implementer cannot satisfy independent review. Findings stay on the PR; the task links them and summarizes unresolved decisions. Material changes need appropriate re-review/current checks. Bring consequential unresolved disagreement to Human review. Current Tyri merges require Amit's explicit approval of the named revision/action; no automatic merge exception is enabled.

## Tyri profile

- Repository: amitsankaran1/Tyri; integration branch main; project Tyri.xcodeproj, shared scheme Tyri.
- Deterministic checks: bash scripts/check.sh. Test doubles do not establish physical Screen Time enforcement.
- CI: Xcode Cloud PR Build, Test and Analyze are required. The automatic PR-open path is verified; the latest complete full Cloud run failed a UI test. See the [CI task](https://app.notion.com/p/3cb16e0e0e3a81438ddbd3a49c70e1ed) for current evidence and [iOS delivery](ios-delivery.md) for configuration.
- UI tests: select an installed Simulator explicitly; use a fresh XCResult/derived-data path and signed Simulator execution where App Group behavior is required. Inspect screenshots of affected flows and attach captioned evidence to Notion. Label fixtures, permission limitations and unverified behavior.
- Device acceptance: affected NFC, authorization/shielding, usage/lockout cycles, cooldowns/breaks, background timing and relaunch/upgrade persistence. Internal candidate first; required physical acceptance precedes broader distribution.
- Delivery: existing App Store app 6757515805 and Amit Internal group only. Approved app-changing main merges are intended to trigger an internal candidate. Documentation-only changes skip release archives. The candidate workflow is provisioned but disabled pending successful setup checks and approval.
- Identity: preserve name.amitsankaran.Block, name.amitsankaran.Block.BlockMonitor and group.com.amitsankaran.Block, required entitlements and app/extension version agreement.
- Authority: investigation and bounded low-risk implementation through a PR are authorized. Blocking/enforcement, persistence/migrations, security/credentials, signing/entitlements and dependencies retain the agreed human scope/review boundaries. No external beta submission, invites/public links or App Store release is implied.
- Receipts: source revision, archive/export and signing evidence, upload acceptance, processing, group availability and required acceptance. Follow release/README.md and release/WhatToTest.txt.
- Recovery: preserve known-good receipt and review data compatibility. A code revert/new candidate does not uninstall a build or undo data changes. Never commit credentials.

## Request a build

File a Tasks record, Project Tyri, Status Inbox: "Build Tyri from approved current main for Amit Internal; produce a fresh build and verify availability." For a bug, make the fix plus internal TestFlight delivery the outcome.

The routine follows the existing PR/run/build rather than producing a new attempt on every poll. A build-only request can skip implementation when no code change is required. Status changes do not approve merges or bypass missing delivery capability. The full remote TestFlight loop remains unfinished; consult the live project readiness before promising delivery.

## Adapt another project

Keep the same phases. Supply one small profile with source/workspace, runtime, claim/executor, meaningful checks and evidence, authorized delivery target/actions, required human/hardware acceptance, credential locations without values, and recovery limits.

For a web app verify the preview in a browser; for a service verify staging/integration behavior and migration compatibility; for a CLI/library verify the built artifact in a clean environment. These examples do not enable deployments or grant new permissions.
