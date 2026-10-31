# Block lifecycle QA — October 31, 2026

Baseline: `b5c9d49`, Tyri 2.3 (5). User reports Twitter is initially shielded by a **usage-limit** block, then accessible a few minutes later. Relationship to opening Tyri vs Twitter is unknown. This report records defects and evidence; it does not claim the phone's exact callback sequence has been captured or fixed.

## Highest-priority usage-limit finding

**P1 — early/stale lock-end callbacks unconditionally end a live lockout.**

`TyriMonitor/TyriMonitorExtension.swift`, `intervalDidEnd`, `.lock`: clears the shield, removes the deadline and re-arms usage without checking the current persisted deadline, block type, or activation identity. This differs from the schedule path, which reconciles actual state.

Reproduction: invoke the production extension's lock-end callback while a lockout deadline is 180 minutes in the future. Observed: `shield=false, deadline=nil, rearmed=true`. The callback QA driver compiles the real extension with test doubles for the OS and persistence services; it proves callback behavior, not that iOS delivered this callback on the user's phone. Run `python3 Tests/CallbackQA/run.py`.

This is the strongest code-level match to the reported symptom. A stale end after monitor replacement or a premature end would grant access and a fresh usage budget. Actual delivery is still a hypothesis requiring physical-device logs. Recommendation: reconcile against persisted lock expiry and a generation/activation identifier before clearing; repeated threshold callbacks should not restart an existing unexpired lockout.

**P1 — stale lock-start callbacks can create an orphan shield.**

The same extension's `.lock` start calls `BlockingActuator.start` even with no persisted lock deadline. Reproduction in the same driver: release the lockout, then deliver start; observed `shield=true, deadline=nil`. This can create shielding the UI does not consider active and cannot expire from its persisted deadline. Recommendation: validate current lock state in both callback directions.

## Other lifecycle defects

**P1 — expired usage lock clears independent manual blocking.**

`UsageLimitManager.reconcileExpiredLocks` and extension `.lock` end call `BlockingActuator.end` without preserving `block.isEnabled`. Reproduction: enable “Block now” on a usage-limit rule, let a usage lock expire, reconcile. The persisted manual flag remains true while the store is cleared. This is an additional combination bug, not an assumption about the user's configuration.

**P1 — stale cooldown releases a later activation.**

`CooldownManager.restoreActiveCooldownsIfAny` completes every expired cooldown against the current block. `completeImmediately` releases the currently active schedule window or usage lock. Cooldowns have only a block ID/deadline, no activation identity, and survive schedule/usage expiry. Reproduction: begin an early-stop cooldown, close Tyri, let that activation finish and a new one start, reopen Tyri. The old cooldown releases the new block. Recommendation: bind cooldowns to the activation they were requested for and invalidate them when that activation ends.

**P1 — 5/10-minute breaks use a 15-minute background re-lock deadline.**

`Shared/BreakMonitoring.swift:50–68`: `breakEnd` uses requested minutes, while the DeviceActivity window uses `max(15, minutes)`. Reproduction on hardware: take a 5-minute break from a schedule/tag block and keep Tyri suspended or killed. Its foreground timer cannot re-lock at five minutes; the registered background endpoint is fifteen minutes. Registration failure is only printed after shields have already been cleared, leaving no reliable background re-lock. Usage-limit blocks do not offer breaks, so this does **not** explain the reported Twitter usage-limit symptom.

**P2 — unchanged usage-limit Save restarts the usage budget.**

`BlockEditorView.save`, timer branch: `limitsChanged || !wasActive` invokes `applyUsageLimit(forceReset: true)`. A rule still accumulating usage is not “active” by `isBlockActive`, so simply opening it and saving unchanged stops/restarts its monitor. Reproduction on hardware: accumulate part of a limit, save without edits, continue usage. Code confirms monitor restart; actual OS usage accounting has not been measured here. Recommendation: only reset when relevant settings change or the user intentionally starts a new budget.

**P1 — registration failures are hidden while logical state can look active.**

`SchedulingManager.lastError` has no UI reader; usage and lockout registration errors are printed only. `startLockout` persists a deadline before registering; a failure leaves logical lock state without an expiry callback. Schedule reconciliation marks running despite a registration failure. Breaks clear the shield before registering the re-lock. These paths are not transactional. Recommendation: return success/failure to callers, show actionable errors, and preserve/recover enforcement on failure.

**Recovery gap — reopening does not repair a missing live usage shield.**

`restoreBlockingIfNeeded` restores only `isEnabled` rules. `reconcileExpiredLocks` handles only expired deadlines; `refresh` reads future deadlines without applying shielding. Therefore an unexpired usage-only lock whose OS setting disappears is not repaired on app reopen. This is a source-confirmed gap, not proof that iOS spontaneously removed the user's shield.

## Validation and limits

- App and monitor built locally with Xcode's iOS 27.1 SDK.
- Existing iPhone 18 Pro / iOS 27.0 UI suite: **4 passed, 0 failures**. `/tmp/tyri-qa-1031.xcresult`; console log `/tmp/tyri-qa-1031-build.log`.
- Foundation schedule suite: **16 passed**, including overnight, weekday ownership, boundaries, DST and full-day intervals.
- Callback fault injection: two incorrect transitions reproduced using the actual extension implementation and explicit OS/service test doubles. This is not OS delivery or app-shield evidence.
- Additional simulator lifecycle/authorization/Safari observations are recorded below after execution.
- Source review covered scheduling, usage limits, manual/NFC state, breaks, cooldowns, persistence, list/block edits, emergency clear and migration. Live NFC and physical Screen Time enforcement are not covered by simulator UI success.
- Production behavior was not changed. Added opt-in Debug diagnostics and QA tests only; no release, commit or upload.

## Device verification needed for the reported Twitter failure

Record threshold arrival, lock registration result, every `lock.<id>` start/end callback, saved lock deadline, block ID/type, app lifecycle and shield readback. Test Twitter immediately after threshold, after several minutes, after reopening Twitter, after reopening Tyri, and after force-quitting Tyri. Repeat with duplicate threshold and stale end/start injections. Acceptance: no early access before the saved lock deadline absent an intentional release; no orphan shield after expiry; reopen preserves and repairs a live usage lock.

## Simulator lifecycle probe observations

Real app managers on the iPhone 18 Pro / iOS 27.0 simulator:

```text
QA baseline website setting present: false
QA manual-after-usage-expiry: enabled=true, websiteSettingPresent=false
QA new schedule before stale cooldown: running=true
QA new schedule after stale cooldown: running=false, releasedUntil=2026-11-01 04:00:00 +0000
QA five-minute break: end=2026-10-31 17:35:39 +0000, registeredEnd=nil
```

The stale-cooldown transition is runtime-confirmed. The missing baseline website setting means this run cannot prove manual-shield removal or actual Safari blocking. The break monitor was not registered in this simulator. The manual-expiry and background-break findings remain supported by source inspection, not successful OS enforcement in Simulator.

## Physical phone attempt

User authorized testing the connected iPhone through iPhone Mirroring. Mirroring returned “iPhone Not Found” after initial and user-requested retries. `devicectl` sees the paired iPhone Duo, but querying the installed Tyri app fails because Developer Mode is not enabled (CoreDevice error 12040/12052; cryptex error 20). No phone app was replaced, no production settings changed, and no on-phone Twitter reproduction is claimed. Awaiting a working mirrored screen for behavioral testing.

Apple API references: [DeviceActivityCenter callback timing](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter), [monitoring registration errors](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror), [ManagedSettingsStore configuration versus effective behavior](https://developer.apple.com/documentation/managedsettings/managedsettingsstore). Store readback alone is not proof of device enforcement.

## Final simulator availability result

Focused test passed after correcting an ambiguous selector in the new test itself: `/tmp/tyri-qa-availability-retry.xcresult` and `/tmp/tyri-qa-availability-retry.log`. Actual Screen Time authorization failed with “Couldn’t communicate with a helper application.” Safari launched successfully; actual shielding remains unverified. The stalled secondary iOS 26.2 run was stopped and is not counted as an app failure.

Totals: 4 existing UI tests passed, 1 diagnostic/availability test passed, 16 calendar checks passed; two incorrect extension callback transitions demonstrated with explicit test doubles. The first focused run failed on test-selector ambiguity and passed after the selector was corrected.

Findings also saved to the existing Tyri Notion project page: https://www.notion.so/2e616e0e0e3a80148841ff8ca2cb3647

## Fix candidate — 2.3 (6)

Usage start/end callbacks now reconcile the persisted deadline; duplicate thresholds keep the original deadline and monitor. Expiry clears state before stopping its monitor and preserves independent manual blocking. Foreground and periodic reconciliation restore unexpired usage shields. No-op usage-rule saves no longer reset the monitor.

Cooldowns are bound to the current schedule window, usage deadline, and manual activation. Old/legacy cooldowns are discarded, and reopening never auto-releases a shield: elapsed waits still require Release. Short breaks use the monitor's end warning at the actual requested deadline, with the later interval end as a backstop. Registration must succeed before lifting the shield; failure keeps blocking on and reports an error. Stale break-end callbacks cannot end a newer break. One-shot windows use full calendar dates and second-aligned deadlines.

The production callback, usage and break helpers pass 12 deterministic checks with explicit OS/store doubles. The opt-in simulator harness now asserts stale-cooldown protection, no release on reopen, and valid explicit release. These tests verify application logic, not real iOS background callback delivery. Apple can defer callbacks until device use; no finite test or app-level change guarantees enforcement after authorization is revoked or the app is uninstalled. Physical Twitter shielding and short-break warning delivery remain acceptance checks for TestFlight.

## Final fix validation and release status

Final source `9084fb6` (tree `bacd7acc0614f56f9edac10757ceb62efd8d57f3`): all **5 simulator tests passed**, plus **12 lifecycle regression checks** and **16 calendar checks**. Final result bundle: `/tmp/tyri-persistence-final.xcresult`. The runtime cooldown probe now reports `running=true, releasedUntil=nil` after stale cooldown restoration, and passes the valid-release and no-auto-release-on-reopen assertions. Failed break registration leaves `breakEnd=nil` rather than starting an unprotected break.

Build **2.3 (6)** Release compilation succeeded. **Not uploaded:** Xcode cloud signing export failed with “No Accounts” / unavailable distribution credentials. Awaiting login-keychain unlock and restored Xcode account access; no App Store release or merge has been performed. The candidate receipt and release runbook record the archive and retry paths. Physical shielding/background timing remains unverified.
