# Overnight schedule fails to enforce selected apps

Evidence: user recording `IMG_0086.MOV` (53 seconds), reviewed October 30, 2026.

## Acceptance criterion and status

The user clarified the core symptom: the block is on, but a selected app remains usable. Success requires actual app access to be shielded, not merely a corrected status label. The current patch calls `BlockingActuator.apply` to restore real Screen Time settings as well as state. However, no physical iPhone is connected; actual enforcement on the reporting device remains unverified. Treat build 2.3 (4) as a candidate fix, not a confirmed resolution. Apple accepted its upload and reported processing; tester availability is not verified.

## Observed

At 00:00–00:15, Focus says “No active blocks” although “No Social Bookends Of The Day” is scheduled every day, 20:00–10:00. The device clock reads 9:39 (AM/PM is not shown; either is inside this overnight interval). At 00:18–00:27, Social Media is linked and Instagram is selected. At 00:30–00:36 and 00:45–00:48, Instagram opens and remains usable without a shield. No runtime logs were supplied, so the exact callback history on that phone cannot be established.

## Cause found in code

Launch re-registers schedules. `applySchedule` previously called `removeSchedule`, clearing the running flag, then relied entirely on a new extension start callback. Foreground refresh only read that flag; it could not recover an active window with a missing/delayed callback. Monitor replacement can also produce an end callback, which previously unconditionally cleared shielding.

Overnight schedules were registered as 20:00–23:59 and 00:00–10:00, creating a gap, resetting breaks at midnight, and checking the morning half against the wrong weekday for non-daily schedules. Very short split segments could fail registration.

## Fix

- Register one continuous DeviceActivity interval, including overnight windows.
- Resolve active intervals from the saved schedule and local calendar; selected weekdays belong to the start day, and the end is exclusive.
- Reconcile shields and running state on registration, foreground/periodic refresh, and either extension callback. Delayed end callbacks cannot clear a currently valid interval.
- Persist the current interval identity to preserve an existing break and its allowance across refresh/relaunch.
- Persist intentional early release through the current window's end, so cooldown/emergency access is not undone by reconciliation.
- Preserve manually enabled shielding when a schedule ends.

Apple references: [DeviceActivitySchedule initializer](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/init(intervalstart:intervalend:repeats:warningtime:)), [nextInterval callback behavior](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/nextinterval).

## Verification

- 16 deterministic calendar checks: both interpretations of the recorded time, start/end boundaries, midnight, selected start weekday, daytime schedules, DST transitions, and a full-day window.
- Debug integration assertions exercise missing callbacks, lost running state on relaunch, repeated reconciliation during breaks, early release, next-window activation, and schedule removal. These run during each UI-test launch and are excluded from Release.
- Simulator UI suite: 3/3 passed on iPhone 17 Pro, iOS 26.2; result bundle `/tmp/tyri-schedule-tests.xcresult`.
- Release archive compiled successfully. Xcode cloud-managed Apple Distribution export verified for both app and monitor; version 2.3 (4), Family Controls, App Group, NFC TAG, and distribution-only entitlements retained. Local development signing was unavailable (`errSecInternalComponent`); the existing documented cloud-signing workflow succeeded.
- TestFlight upload receipt: `release/builds/2.3-4.json`.
- Physical Screen Time enforcement and background extension delivery require an iPhone; simulator success does not verify Instagram shielding on hardware.

## Device acceptance test for TestFlight

1. Install the candidate over the current build without deleting saved lists.
2. During an every-day 20:00–10:00 window, open Tyri. Confirm the block appears active and Instagram displays the Screen Time shield.
3. Force-quit/reopen Tyri during the window; verify status and shield remain active.
4. Test a Friday-only overnight schedule into Saturday morning and verify release at its configured end.
5. Take one break; reopen Tyri during it. Confirm it stays on break, then shields again at expiry without granting a second break.
6. Complete an early-disable cooldown; reopen Tyri. Confirm release persists until the next scheduled window.
7. With Tyri closed, verify the next start and end on a physical phone.
