# Blocking reliability investigation

Candidate: 2.4 (4), branch `fix/blocking-reliability`, based on shipped 2.4 (3). AI work remains on `develop/2.4` and is excluded.

[Live Notion investigation and usability proposals](https://app.notion.com/p/41016e0e0e3a818e843ec19a9777c384).

## Confirmed app-code failures

- Foreground did not repair lost usage registrations.
- Manual shield application happened after synchronous monitor registration.
- At 20 activities, a consumed usage monitor occupied the slot needed for lockout expiry.
- Shield audit missed dropped typed-domain writes, empty targets and oversized selections.
- Missing Screen Time access could fail manual activation without visible feedback.

Candidate repairs missing registrations only with approved permission; healthy usage counters remain intact. Live lockouts recover without starting another allowance. Manual shields are applied before registration. Consumed allowance monitors release their slot after shielding. Error reporting includes exact settings readback and an explicit permission alert.

Readback is not proof of effective shielding. No connected physical iPhone is available, and the affected iPhone 15 Pro's iOS version is unknown. Do not mark the field incident resolved until on-device acceptance.

## Repeatable logic checks

Run from this checkout:

```
python3 Tests/CallbackQA/run.py
python3 Tests/ShieldQA/run.py
python3 Tests/ActivationQA/run.py
python3 Tests/UsageRecoveryQA/run.py
python3 Tests/SchedulingQA/run.py
```

Current results: 895 callback/lockout checks, 16 shield checks, seven activation checks, six usage-manager checks, ten scheduling-manager checks. OS services are doubles, while tested decisions are extracted or compiled from production sources. Most callback checks cover all 287 supported duration values; counts are not independent real-device scenarios.

`QA_REVISION=4a39721` or `QA_REVISION=7334f2b` runs the callback suite against older source. Both yield 894 passes and one capacity failure. Activation and Shield runners also support `QA_REVISION` for reproduction. Expected baseline failures must not be treated as candidate failures.

Additional Foundation checks: 16 schedule calendar/DST cases; seven schedule ownership cases (`TZ=UTC` required); reported-progress generation/reset and all 287 milestone ranges; 25 domain/end-description checks.

## Simulator evidence

BlockingReliabilityTests covers a real UI denial path and release-accessible diagnostics. DurationTests covers picker boundaries, cancellation, persistence and display fixtures. Review fixtures do not authorize Screen Time or synthesize app tokens.

Initial test corrections: seed an inactive timer; wait for editor navigation; tap the actual switch hit target; use a unique block-row accessibility identifier because error headers can repeat block names. Original failed runs remain recorded. A sampled iOS 17.5 process spent its main thread in SwiftUI layout during diagnostics navigation with a 3.3 GB footprint; the diagnostic report now uses a simple scroll view instead of a single oversized List cell. Retest required.

## Remaining field checks

Real individual-app and mixed-list shielding; schedule/threshold delivery while app is closed; permission revoke/regrant; stale/expired tokens; reboot and timezone changes; named-store capacity and corrupted persisted selection data. These cannot be established by a simulator or deterministic doubles. Missing-list counts and registration/shield/callback diagnostics support investigation. No automatic token-refresh or persistence-format migration is included without evidence.

## Usability

Current controls expose independent state machines: manual activation, schedule windows, usage allowance/lockout, one-use breaks, stop-early waiting/confirmation, permission and enforcement health. Active actions now precede configuration. Manual activation explains Save and its indefinite duration. Larger proposals are recorded in Notion: apps first, timing next, a confirmation sentence, explicit end conditions, and consolidated recovery actions.

## Release gate

Latest source must pass relevant logic checks, simulator review and Release archive/signature/profile verification before uploading. The user authorized upload after checks. Record the final source commit, SHA-256, Apple build ID, processing state and internal tester assignment in `release/builds/2.4-4.json`. Do not equate upload success with tester availability or physical enforcement.
