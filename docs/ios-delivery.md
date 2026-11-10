# iOS checks and TestFlight delivery

Implementation task: https://app.notion.com/p/3cb16e0e0e3a81438ddbd3a49c70e1ed

This is the proposed configuration, not a claim that cloud CI or automatic delivery is enabled. Provider and automatic release trigger await Amit's decision. The hourly bug routine remains documentation-only until the iOS execution path is verified.

## Source prerequisite

On November 9, 2026, PR #24 was merged with Amit's reconciliation authorization. Canonical `main` is now `cebf0b194258d3a7e979465c06d29df59382aacd`, containing the released 2.4 build 7 source and its receipts. The release receipt identifies built source `068d1904e719d3daca4d50ef91c719f232e85ca0`, successful processing and availability in `Amit Internal`; physical enforcement remains unverified. Verify the current Apple account record before selecting another number.

Workflow PR #25 includes that main merge and is checked against the combined source. Keep `deferred/nl-creation-2.4` out of this rollout. The one-time reconciliation does not authorize future automatic merges or release triggers.

## Proposed Xcode Cloud configuration

Keep two workflows using `Tyri.xcodeproj`, shared scheme `Tyri`, and a supported pinned Xcode/macOS pair. Verify the cloud toolchain against the local Xcode 27.2 baseline; do not select an unavailable cloud version based on the local installation.

| Workflow | Start | Checks/actions | Delivery |
| --- | --- | --- | --- |
| Tyri PR checks | PR creation/update targeting `main` | Deterministic harnesses, simulator build/test, analyze | None |
| Tyri internal candidate | App-affecting changes merged to `main`, if approved | Deterministic harnesses, simulator test, Release archive, signing | Post-action to existing `Amit Internal` only |

Configure file/folder conditions so documentation-only merges do not produce new binaries. Include app, shared source, extension, resources, project/scheme, tests, build scripts and release configuration; do not use only `*.swift`. A required PR check must still report for documentation-only PRs: initially run the PR workflow for all PRs and filter only the candidate workflow. Workflow/test changes can themselves require a candidate when they affect build behavior.

For Xcode Cloud, executable `ci_scripts/ci_post_clone.sh` can call `bash scripts/check.sh`; a nonzero exit must fail the workflow. Do not install ad-hoc downloaded dependencies in the hook. Keep signed distribution out of PR workflows and never expose custom delivery secrets to PR code. Inspect cloud signing access and any fork behavior before enabling PR triggers.

Archive for **TestFlight and App Store** eligibility while distributing automatically only to the internal group. This preserves the option to promote the same accepted binary later. Choosing **TestFlight Internal Only** would require another binary for external testers. Neither selection authorizes an App Store release or external beta submission.

## Agent and review loop

1. A filed task retains its report, scope and observable acceptance criteria. Once app-code pickup is explicitly enabled, the dispatcher checks out current canonical source, reproduces the bug, implements in an isolated branch, runs relevant checks and opens/updates one PR.
2. Cloud PR checks apply to the current PR revision/merge candidate. The agent reads actual failed logs, fixes failures within scope and updates the same PR. It does not weaken tests or change signing/release policy to make a check green. Retry infrastructure failures on the existing run when supported; repeated failures or scope changes get a concrete Human review checkpoint, not an unbounded retry loop.
3. Amit reviews the diff, test evidence and labeled screenshots. Required checks must pass for the latest revision; old approval or old green checks do not cover new commits. Amit approves and merges under the current policy.
4. The candidate workflow checks the merged source again before archiving. PR success alone does not verify the exact merged source. A failed test/archive/signing step prevents delivery.
5. Record the source, CI run and version/build before treating a binary as a candidate. Mark delivery complete only after Apple's processing and group availability are verified.

Use GitHub and the CI provider's native run/cancellation identities. Notion statuses remain descriptive; do not add statuses for each build phase or trigger deployment from a status change. A newer main commit must not silently cancel an upload whose outcome is unknown: reconcile the existing Apple build first. Multiple requested fixes can share a candidate, but each task must name the candidate that actually contains its fix.

## Signing and numbering

- Existing app ID: `6757515805`; team `DAG83US2FV`.
- App: `name.amitsankaran.Block`; monitor: `name.amitsankaran.Block.BlockMonitor`.
- Both require Family Controls and `group.com.amitsankaran.Block`; the app also requires NFC `TAG`.
- Verify automatic distribution signing for **both** bundles, the expected application identifiers, Store profiles, and Release entitlements. Simulator compilation cannot establish signing readiness. Do not make the historical ad-hoc archive workaround the cloud signing design.
- Use one authoritative CI build counter; set its initial value above the highest uploaded build after inspecting App Store Connect. Keep marketing versions controlled in source. Verify app/extension versions agree in the archived product. Do not let local and cloud uploads independently allocate the same number; reserve a number explicitly for exceptional local releases.
- Retain symbols and archive/run references. Secrets stay in Apple/provider storage, with names and access requirements documented; no credential values in Git, Notion or logs.

## Delivery evidence and device acceptance

For every candidate record: task(s), merged SHA, PR(s), CI run URL, Xcode/OS, checks and limitations, marketing version/build, signing/capability verification, archive identity, upload result, Apple build ID, processing result, testing notes and export-compliance resolution, group and tester availability, device checklist and acceptance result.

Use the existing `release/builds/*.json` receipt convention without committing credentials or CI build products. A durable checkpoint can first live in the Notion task with the CI/Apple references; a follow-up receipt-only commit must not trigger another release. Do not claim CI produced a receipt until that reporting path is actually implemented and tested.

Apple's successful upload is an intermediate result. Reconcile an uncertain upload by build number/run and Apple processing before retrying; never blindly rebuild/re-upload the same number. An available build must be assigned to `Amit Internal`, with the intended tester eligible to install it. Do not invite new testers or change audience implicitly.

Simulator tests and OS doubles establish selected logic/UI behavior. For affected NFC, Screen Time and persistence, Amit installs the named internal version/build and verifies the affected physical behavior. Provide a short task-specific checklist covering relevant authorization, shielding, NFC, background/timing, relaunch and upgrade persistence paths. Record device/OS and observed results. Broader distribution waits for acceptance of the same binary; changed code requires fresh acceptance as appropriate.

If a task promises internal delivery only, it may complete once that agreed outcome is verified. If it promises physical acceptance or broader delivery, keep it in Human review until that remaining outcome is met. A merged PR alone does not satisfy promised delivery.

## Failure and recovery

Build/test failure returns to the same PR/run and task. Signing/account failures require the exact account action, without requesting secrets in chat. Processing failures preserve the rejected build receipt and Apple's message. CI green plus missing tester availability is still incomplete delivery.

Pause the release workflow when its source, entitlement or audience assumptions are uncertain. Preserve the last known-good receipt. A revert produces a **new** build; it does not downgrade installed apps or restore user data. Review data compatibility before using a replacement candidate. Removing a build from a tester group does not uninstall existing copies. External testing, public links, beta review and App Store submission remain separate explicit actions.

## Proving the setup

1. Reconcile the source and provider decisions; verify Apple/GitHub access, signing and tester group.
2. Provision PR checks, run a known PR, inspect logs/results and establish the required latest-revision check in GitHub.
3. Run one explicitly authorized candidate from the reconciled source. Verify both bundle identities/versions/capabilities, processing and internal availability; capture and inspect the setup/result UI and attach captioned screenshots to the Notion task.
4. Test a failed check prevents candidate delivery and a documentation-only merge does not archive. Test post-merge app changes trigger the configured workflow without another chat instruction only after that trigger is approved.
5. Add CI result collection to the existing hourly agent so it updates the original task and continues eligible fixes from failed logs. Demonstrate the complete bug → PR → review → merge → candidate → availability loop before widening app-code pickup. Scheduler and build execution are separate responsibilities; do not assume the scheduler has Xcode.

Apple references: [workflow configuration](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference), [custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [distribution](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution), [TestFlight post-actions](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight).
