# Blocking lifecycle investigation and acceptance gaps

Inspected baseline: `a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698`, current main on November 14, 2026. **Build 2.4 (37) is now verified as this revision**; see the Apple build/run evidence in [provenance](PROVENANCE.md). The resumed audit found and reproduced an expiry-rearm defect in this source: an empty cleanup array stops every native monitor. The bounded fix is described below. Actual-device counting and shielding acceptance remain pending. Final execution results belong in the progress/check records, not inferred from test-file presence.

## Reproduced monitor-loss cause and fix

Apple's [`stopMonitoring(_:)` contract](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/stopmonitoring(_:)) says an empty array stops **all** activities; a nonempty array stops only the named activities. The earlier native doubles incorrectly treated an empty array as a no-op. This masked a production failure, including in the previously passing lifecycle simulations.

The normal sequence in build 37 is:

1. A usage threshold starts the fixed 180-minute lock and invalidates the consumed allowance's ledger owner.
2. At expiry, `startUsageMonitor` reads that inactive ledger: neither confirmed nor pending owner remains, so `oldActivities` is empty.
3. Native registration succeeds, the next allowance is published, and the legacy registration receipt is written.
4. The trailing `stopMonitoring(oldActivities)` then stops **every** native monitor, including that fresh allowance and unrelated schedule/break/lock monitors. Persisted configuration and the success receipt remain.
5. Foreground recovery later observes the missing allowance and registers a replacement, starting a new counter. This supplies a concrete causal explanation for registration at 00:43 followed by counting only after reopening near 04:43. The old device logs cannot prove the precise generation sequence; physical acceptance is still required.

The fix skips native cleanup when there are no names to retire. A second guard prevents empty filtered `stopUsageMonitor` cleanup from stopping unrelated monitors after retirement was already acknowledged (for example, timer-to-tag conversion followed by deletion). All 12 production native stop call sites were audited: the capacity path already guards its dynamic array, schedule removal uses three fixed names, and the remaining eight use singletons. Healthy native owners/counters, schedules, saved data and enforcement policy are unchanged.

`Tests/UsageRearmQA/run.py` compiles actual production callbacks, usage/lock helpers and ledger/transaction code with a deterministic clock and a native double corrected to Apple's contract. It exercises two 10/180 cycles, successful receipt with a surviving next allowance, unrelated-owner survival, duplicate expiry/stale threshold preservation, and acknowledged empty teardown. `QA_REVISION=edd74e9 python3 Tests/UsageRearmQA/run.py` replays the unfixed production version against the same corrected boundary. This regression fails on the old source at the actual missing-native-monitor invariant; it does not inject an unexplained deletion. Other stateful native doubles also model empty stop and event removal correctly.

The earlier injected-native-loss experiment below remains useful for diagnostic identity coverage, but is no longer the only evidence of how monitor loss can occur. Real Screen Time usage accumulation is not implemented by the doubles.

## Production path

1. `BlockEditorView.save` validates the draft under `EnforcementTransaction`, updates `BlockStore`, and flushes saved rules before `ForegroundRecovery.requestAccepted`. Its final lease release hands native effects to the recovery service off MainActor. Rule persistence is distinct from successful registration.
2. `requestAccepted` owns a bounded background assertion. `request` reconciles deadlines and shield intent, checks storage and authorization, and coalesces concurrent requests with `rerunRequested`. An expired assertion closes admission; a later activation reconciles durable state.
3. `ForegroundRecovery.makePlan` derives semantic context from persisted rules and selections. Observed matching pending registrations are promoted; observed matching confirmed registrations are retained. Only missing/mismatched owners receive a new reservation. A healthy allowance is not restarted on reopen.
4. `RecoveryJob.execute` invokes `DeviceActivityCenter.startMonitoring` off MainActor and outside the file lease. Optional progress-event failure falls back to the limit event. Native return is not proof of actual usage counting.
5. Completion reloads context and reservation identity. `MonitorLedger` rejects obsolete completions; a callback can promote a pending owner before native return. Usage generation publication clears old progress without inventing a reported zero.
6. `TyriMonitorExtension.eventDidReachThreshold` loads the saved rule and groups, accepts the generation, records valid progress events, or calls `UsageMonitoring.startLockout` for the limit. `startLockout` preserves an existing future deadline, otherwise persists a fixed deadline and shield intent, retires the consumed allowance, and registers lock expiry.
7. Shield writes run after releasing the state lease. `BlockingActuator` persists revisioned intent, rechecks ownership on completion, and retries pending intent. Settings readback establishes settings agreement only; it does not establish an effective shield on a target.
8. Lock callbacks reconcile the persisted deadline, not callback order. Early/duplicate callbacks cannot shorten or extend the deadline. On expiry, `releaseExpiredLock` clears timed ownership, preserves manual ownership, and rearms a fresh allowance when no current usage monitor or pending owner exists. Foreground recovery separately handles missed expiry/rearm.

## Earlier evidence and competing explanations (before empty-stop discovery)

The reported sequence is reopen → usage counts → block after another ten minutes. Exact reopen time, selected target, and preceding transition remain unknown. The 17:43:52 registration, 21:43:21 threshold, 21:43:22 lock start, and 21:47:45 settings readback do not establish counting onset or effective shielding.

On the inspected revision, the exact diagnostic `Registered allowance; progress events: true` comes only from `UsageMonitoring.startUsageMonitor`. Its sole production caller is the expiry-rearm path. Ordinary Save registration uses `ForegroundRecovery` and did not emit that diagnostic. With build37 now attributed to this revision, the recorded registration identifies the expiry-rearm path. It still does not identify the registered generation: the old diagnostic omitted that identity, and app recovery could later replace it without updating the same diagnostic slot.

| Explanation | Evidence that would discriminate | Present conclusion |
| --- | --- | --- |
| Save/recovery did not complete before suspension | Save/admission, native request/return, reservation/publication and foreground times | Earlier fixes cover several interruptions in doubles; recurrence not reproduced |
| Expiry rearmed but native counting/callback delivery stalled | Expiry and allowance generation, callback log before reopen, target usage timestamps | Plausible given diagnostic origin; not proven |
| Native all-day interval behaves differently on affected OS | Release-device reproduction using same generation without foreground, compared to documented behavior | No evidence justifies changing the schedule |
| Generation or late completion replaced a working counter | Correlated reservation/publication identities and injected interleavings | Existing tests and added stress preserve healthy/current identities |
| Shield was delayed despite timely threshold | Actual target shield observation vs threshold/foreground times | Cannot infer from settings readback; does not alone explain subsequent ten-minute counting |
| Target selection or authorization differed | User checks the selected target and approved authorization; sanitized target counts | Selection identities intentionally not logged; device verification pending |

Apple documents callbacks beginning when registration occurs during an ongoing interval, and schedule initialization documents an immediate interval-start callback when the current time lies inside it. This contradicts treating “midday registration must wait until midnight” as an established platform rule. Apple also documents that registering an existing activity overwrites its schedule/events, reinforcing the need to preserve healthy registrations. These documents describe the API contract, not proof that the affected device followed it. Sources: [startMonitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)), [schedule initializer](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/init(intervalstart:intervalend:repeats:warningtime:)).


## November 15 follow-up evidence

The additional device reports show the earlier lock deadline at `00:43:21Z`, an allowance registration at `00:43:24Z`, and a usage-interval start at `04:43:24Z` for generation `r-5FEC009E-10AE-48D1-B7EA-6A94B3B3E970`. The report captured at `04:43:32Z` showed a registered usage monitor, ten events, and no lock. Amit said the app had just been opened to check. The next capture at `04:55:28Z` showed a matching-generation threshold at `04:55:17Z`, lock start at `04:55:18Z`, and deadline `07:55:17Z`.

This confirms an expiry-path registration receipt shortly after the previous deadline and later successful threshold-to-lock processing. It does **not** establish that the generation registered at `00:43:24Z` is the one receiving the interval callback four hours later, nor that the selected target was used throughout that gap. The legacy registration receipt lacked identity and was not updated by app recovery. The four-hour spacing is observed, but the production code contains no corresponding four-hour rearm delay; it is not evidence of a timezone conversion defect.

The added deterministic regression deliberately removes a rearmed monitor at the native boundary, advances its clock four hours, then runs actual foreground recovery. It reproduces the diagnostic ambiguity: the old expiry registration receipt remains while recovery creates a different generation. This demonstrates a competing explanation permitted by production logic, **not** why iOS lost or delayed a monitor on the affected device. Existing healthy-monitor checks still prove that an observed matching owner is retained by app logic.

Diagnostics now keep bounded usage-specific request/return slots so lock registration cannot erase allowance timings. A separate replacement receipt identifies the prior/current opaque names and distinguishes absent observed monitor from changed saved inputs; an observation receipt identifies a preserved/promoted owner. Usage interval callbacks retain a separate receipt labeled confirmed, pending, or stale identity. No selection tokens or semantic-context strings are logged. These are latest-per-kind receipts, not a complete event history, and interruption before commit can still omit a native outcome.

Apple's [nextInterval documentation](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/nextinterval) describes interval boundary times as earliest callback times and says callbacks occur when the device is used. A four-hour wall-clock gap alone cannot establish a counting delay; the selected-target usage and actual foreground time remain required evidence. The existing registration/threshold timestamps should be correlated with these new identity-preserving receipts on an explicitly authorized candidate.

## Scenario matrix

Test harnesses compile production logic with explicit native doubles or extract production methods; they are not physical acceptance. Existing suites below were inspected for coverage. Their final pass/fail status must be taken from the final revision's check log.

| Area / invariant | Automated coverage | Remaining boundary |
| --- | --- | --- |
| Save during registration/recovery; immediate background; expiration and retry | `ForegroundRecoveryQA`: stalled native calls, queued final-observation Save, inactive Save, assertions, expiration | Real suspension/force-quit and native IPC timing |
| Initial and repeated 10/180 cycles; no premature or permanent timed lock | New `CallbackLifecycleStressQA`: 100 cycles, fixed deadlines, early/end/warning callbacks, fresh next allowance | Real ten-minute use and three-hour expiry without reopening |
| Healthy counter survives reopening | `ForegroundRecoveryQA` retains matching observed monitor; callback stress rejects stale reset | Native counter contents cannot be read by these doubles |
| Stale, duplicate, out-of-order callbacks and generations | New callback stress: 2,767 transitions at seed `370026601`; `LifecycleStressQA`: production-ledger property traces | OS callback scheduling/delivery; actual multi-process extension lifetime |
| Cancellation, partial failures, late success, app/extension races | `ForegroundRecoveryQA`, `CallbackQA`, `StateMachineQA`, `MonitorLedgerQA` | Interrupted native operations on device; not crash-atomic across APIs/preferences |
| Midday, midnight, DST, timezone | `ScheduleWindowTests` tests calendar windows, including DST; UTC deadline code inspected | Native usage-counter reset and timezone-change behavior remain untested |
| Usage, manual, schedule, breaks, temporary sessions and cooldown overlap | `StateMachineQA`, `MutationStateQA`, `ScheduleStateQA`; callback stress preserves manual and unrelated owners | Physical shield union, native timing and long background lifetimes |
| Selection edits and deleted/referenced lists | `MutationStateQA`, `UnreadableStoreQA` check replacement/persistence and preserve missing-list protection | Real app/category/web token semantics and picker changes |
| Shared data unavailable/corrupt; interrupted writes and upgrades | `StoreDurabilityQA`, `UnreadableStoreQA`, `MigrationStateQA`, `TransactionQA` | Device-protected storage while locked; crash at every write boundary not exhaustively covered |
| Authorization revoked/regranted | `ActivationQA` checks revoked admission; recovery source guards authorization | OS revoke/regrant, lost native monitors, and real shield restoration |
| Emergency Access and tag boundaries | `MutationStateQA`, `ForegroundRecoveryQA`, `NFCStateQA` | Real NFC; lost-tag feature remains deferred |
| No UI assertion of unproven enforcement | Existing presentation suites; pending-vs-reported state inspected | Final simulator/UI results and captioned screenshots recorded separately; no device claim from screenshots |
| No native IPC under file lease/MainActor; suspension admission | `NativeBoundaryQA`, `SuspensionLockQA`, `TransactionQA`, `ForegroundRecoveryQA` | Native IPC itself may stall; unavailable-storage follow-up is separately reviewed |

New callback stress passed against current-main production logic with native doubles. It is replayable with `TYRI_CALLBACK_SEED=370026601 python3 Tests/CallbackLifecycleStressQA/run.py`. On failure it prints a cycle-local trace. The separate ledger stress suite supplies deletion-minimized failing operation traces. Neither suite reproduced the reported device recurrence.

## Physical-device acceptance: pending

No suitable authorized physical-device test was completed. Do not change existing real restrictions, reset data, or distribute a candidate as part of these steps without the separate authorization required for the named revision.

After an approved release/TestFlight candidate is available:

1. Record version/build, exact source receipt, iOS version, timezone, and authorization status. Use the existing selected app only with Amit's authorization. Run without an attached debugger.
2. Save 10-minute allowance / 180-minute lock. Record Save time and immediately leave Tyri. Do not reopen it. Use the selected app beyond ten minutes, recording start/end times and the first actual shield appearance.
3. Verify the target is actually blocked. Record when shielding starts. Collect diagnostics only after the shield observation, noting the exact Tyri reopen time so foreground recovery cannot be mistaken for independent enforcement.
4. Leave Tyri closed through the original 180-minute deadline. Verify the selected app becomes usable at that deadline; do not shorten the lock or reset configuration.
5. Use the app for another ten minutes without reopening Tyri. Verify a second actual shield and the new fixed lock deadline. Record the second generation/registration/callback times afterward.
6. Correlate foreground, registration request/native-return/publication, expiry and threshold timestamps. If the failure recurs, preserve the diagnostics and exact target/preceding transition rather than resetting a healthy monitor.

Build37 source verification and a production-path monitor-loss reproduction/fix are complete. Physical-device acceptance remains a prerequisite for closing the original bug: a corrected native-contract double does not establish actual usage accumulation or effective shielding on Vyshu’s device.
