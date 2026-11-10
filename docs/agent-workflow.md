# Agent work and delivery

Task: https://app.notion.com/p/41316e0e0e3a819793daf1454045a641

## How to use this

For new Tyri bugs, file the report through GB, Dot, Instinct or another connected agent in Tasks with Project = Tyri and Status = Inbox. The native hourly routine checks for eligible reports; no second chat handoff is needed. The first implementation pilot covers source-backed documentation corrections through a draft PR. App-code changes and iOS testing/delivery still need the separate verified execution path.

For other work, or projects not yet enabled for automatic pickup, start from the coding agent's chat with a task link and an observable outcome. For example:

> Work on [Notion task URL] in Tyri. Follow docs/agent-workflow.md. Reproduce the bug, implement the fix, run the relevant checks, and open a draft PR. Update the task with evidence and the decision you need from me.

The agent reads the task and project profile, resolves material scope questions, implements and checks the change, then sends you the PR and evidence. You do not need to move statuses by hand. Check Human review for a concrete decision; reply in the chat that owns the work:

> Make these changes: [specific feedback].

When satisfied, approve the named revision and requested action explicitly. For the initial workflow, merge the approved PR yourself in GitHub. To request an iOS candidate:

> Prepare and upload the approved [commit/PR] to Tyri's existing internal TestFlight group. Verify processing and availability, and give me the affected physical-device checks.

The agent uses the existing release runbook. Account/signing access may require your action. Install the reported version/build in TestFlight, perform the listed device checks, then reply with the version/build and results. Broader distribution of affected NFC, Screen Time or persistence behavior waits for that acceptance. Approve broader distribution separately, naming the build and group.

To resume in another session, send the same task link and say "Resume from the latest checkpoint; inspect the existing branch and PR before starting another attempt." If delivery fails, ask to resume that delivery attempt; the agent checks the existing upload/run before retrying.

For another software project:

> Set up the workflow from [link to this document] for [repository/project]. Inspect its existing checks and release process, add its project profile, and link it from the Notion project. Start with chat authorization and human merge review.

That project gets its own commands, candidate destination and release permissions. Future tasks then use the same start/review/resume prompts with that project's task link.

**Available now:** the native hourly routine is active for eligible new Tyri documentation bugs through a draft PR. This branch adds the workflow, PR template and `bash scripts/check.sh`. App-code pickup, auto-merge and automatic TestFlight delivery still require their follow-up setup. Project checks do not run automatically until CI is configured; agents must run and report applicable checks explicitly.

## Shared workflow

1. Amit authorizes a named task in chat, or the enabled project's standing pickup policy authorizes a newly filed clear bug. The approved Tyri pilot uses one hosted dispatcher checking every hour, with one implementation per project; see [the dispatcher setup](task-dispatcher.md). Record scope, acceptance criteria and requested destination in the task. Status and ownership never grant authority. The initial documentation-only pilot is active and its native execution-through-PR path is verified.
2. Read the latest task, project instructions and repository instructions. Continue the existing attempt when appropriate. Use an isolated branch/worktree and record its location. If scope has materially changed, resolve the change before implementing it.
3. Implement independently within scope. Select checks that exercise the changed behavior; for bugs reproduce the failure when feasible. Record source revision, commands, results, environment and unverified acceptance criteria. For UI changes, inspect screenshots and attach captioned evidence to the project's Notion task/page, labeling fixtures and limitations.
4. Prepare a PR with the task link, resulting behavior, validation and recovery implications. Use Human review when a concrete result needs Amit's decision; say exactly what decision is needed. Revisions return to In progress. Until an explicit eligibility policy is approved, Amit approves merges.
5. Deliver only to the destination authorized for the project/task. Report merge, artifact creation, availability to users and acceptance separately. A successful upload or build is insufficient evidence of availability.
6. Mark Done when the agreed task outcome is verified. If delivery was promised, include delivery evidence. Keep missing checks explicit. Use Blocked for a missing input/action preventing progress, not ordinary review. Retries and CI runs stay in the evidence, without extra task statuses.

The same steps apply across projects; each project supplies a small profile describing its commands, environments, required manual checks, delivery authority and recovery procedure. Copy the template below rather than building a universal deployment engine. GitHub/CI retains execution state; Notion retains scope, decisions and evidence.

## Tyri profile

- Source: `amitsankaran1/Tyri`; default integration branch `main`; Xcode project `Tyri.xcodeproj`, shared scheme `Tyri` (includes the app, monitor and UI test target).
- Deterministic checks: `bash scripts/check.sh`. Runs all checked-in `Tests/*/run.py` harnesses plus the calendar, papercut and (where present) usage-progress suites. OS/store doubles do not establish physical Screen Time behavior.
- Compilation: `xcodebuild -project Tyri.xcodeproj -scheme Tyri -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tyri-agent-build CODE_SIGNING_ALLOWED=NO build`. Use a fresh derived-data directory per attempt.
- UI checks: select an installed simulator explicitly and run `xcodebuild -project Tyri.xcodeproj -scheme Tyri -destination 'platform=iOS Simulator,id=<UDID>' -resultBundlePath <fresh-path>.xcresult test`. Choose relevant NavigationTests scenarios after inspecting them; report what actually ran. Check adaptive layouts and preserve unsaved edits when affected.
- Device acceptance: NFC scans, authorization, real shielding, category deselection, usage/lockout cycles, breaks, cooldowns, relaunch/upgrade persistence, and timing/background behavior as affected. Simulator screenshots and test doubles cannot substitute for these checks. Record device/OS, version/build and observed behavior.
- Distribution: use the existing app record and bundle IDs; preserve app and monitor entitlements, Family Controls, App Group and NFC capability. Follow `release/README.md`. Version/build numbers must agree across app and extension and be unused in App Store Connect. Record source SHA, archive/export identity, signing verification, upload result, processing result and tester-group availability. Never commit credentials.
- Build service and automatic delivery trigger/audience are not selected. See [the proposed iOS delivery setup](ios-delivery.md), including the released-source/main discrepancy that must be reconciled before activating release triggers. Amit approved an internal TestFlight candidate before physical-device acceptance, with device acceptance required before broader distribution for changes affecting NFC, Screen Time enforcement or persistence. The existing internal group is the proposed automatic audience; automation itself is not yet configured.
- Recovery: preserve the previous known-good release receipt. A code revert creates a new candidate; it does not uninstall an iOS build or undo user data changes. Review persistence compatibility before distributing a replacement. No App Store release or external beta review submission is implied by a TestFlight task.

## Project profile template

Keep one profile in each repository and link it from the existing Notion project:

- Repository, integration branch, runtime/toolchain prerequisites.
- Fast checks, integration checks and build command; where evidence is saved.
- UI evidence and manual/hardware checks that automation cannot establish.
- Candidate destination (preview URL, internal beta, staging service or package artifact), delivery command/service and availability check.
- Promotion to production/public distribution: who authorizes it and what evidence is required.
- Credentials: required secret names and secure host/location only, never values.
- Recovery: previous artifact/deployment and data/schema compatibility limitations.

For a web app, replace simulator and TestFlight steps with browser/integration checks and a verified preview URL. For a service, use integration/contract checks and staging health checks, including migration compatibility. For a CLI/library, build an installable package and smoke-test that artifact in a clean environment. These are adaptation examples, not enabled deployments or project-wide permissions.

## Automation boundaries

Future auto-merge eligibility and delivery policy: https://app.notion.com/p/41316e0e0e3a8115b74fd0c8ce92b618

Eligibility is evaluated against the current diff and required evidence, not an agent's confidence label. Tests/review must apply to the revision being merged; new commits invalidate prior evidence as appropriate. Mixed or uncertain changes require Human review. Blocking behavior, persistence, signing, entitlements and dependency changes require human review under the current agreement.

Use the CI provider's native concurrency and run identities. Resume or retry a known run before creating another upload; check whether Apple accepted an upload before retrying an uncertain result. Do not start deployment from a Notion status change. Build-time secrets remain with the selected delivery host, separate from untrusted PR checks. Auto-merge, unattended pickup and automatic deployment are not enabled by this document.
