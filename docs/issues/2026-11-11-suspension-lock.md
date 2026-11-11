# Shared enforcement lock during suspension

Task: https://app.notion.com/p/41516e0e0e3a819eaba8cac14cf8776a
Baseline: main at 17eb611 (reported TestFlight 2.4 (30)).

The reported recovery chain acquired `enforcement.lock`, reconciled a schedule,
and synchronously applied/cleared ManagedSettings while the outer transaction
still held flock. A stalled daemon reply could therefore overlap suspension.
The raw device crash attachments live on the filing agent's host, not this Mac;
the source-level lock hazard is independently reproduced by `SuspensionLockQA`.
This is structural reproduction, not reproduction of RunningBoard's device kill.

## Change

State transactions persist a versioned shield intent. Nested shield operations
coalesce, and the outermost transaction releases flock and its recursive mutex
before effects execute. Recovery runs those effects off MainActor. Each native
completion compares durable revision, tracks overlapping operations, and replays
a newer intent if an old write landed late. Chunk high-water counts survive
concurrent shrink/clear; pending clear tombstones survive owner deletion.
Successful unchanged intents avoid repeated writes within an active session.
A new foreground session verifies settings again rather than trusting a cached
successful apply across suspension or process launch. Failed readback remains
retryable. An orphaned in-flight marker after process death conservatively causes
retries rather than treating an uncertain native result as applied.

Resigning active cancels recovery, clears reruns, disables new shield effects,
and invalidates schedule, usage and break timers. The fast lane recomputes
schedule windows before replay, so an old apply cannot race a stalled observation
on resume outside its window. Remaining native property calls
and completion leases are gated; interrupted effects stay retryable. Foreground
replays pending intents, including clears for deleted/expired owners. UIKit
background assertions cover recovery passes and short transactions; expiration
closes admission without unlocking another thread's transaction.

## Verification

- `QA_REVISION=17eb611 python3 Tests/SuspensionLockQA/run.py` fails with actual
  kernel-flock contention during 14 ManagedSettings double writes; current source
  reports zero and passes.
- `bash scripts/check.sh`: deterministic suites, including actual periodic timer
  invalidation/restart and a UIKit background-task double exercising expiration,
  assertion cleanup and zero post-expiration lease admission.
- ShieldQA: 29 cases, including two-second stalled native IPC with independent
  flock acquisition, cross-process replacement, eight-chunk shrink/clear races,
  inactivity between native calls, pending replay, deleted-owner clear and
  retrying transient post-unlock contention without another callback.
- Signed Debug simulator build; all six BlockingReliabilityTests passed on
  iOS 27.2. The new UI test waits 35 seconds in the background, verifies the
  unsaved editor value survives, then performs three additional Home/resume cycles.
  Screenshots were inspected and attached to the Notion task. These use empty
  picker tokens and seeded progress; they do not prove Screen Time enforcement.
- An initial unsigned UI attempt lacked App Group entitlement and failed its
  launch harness. The ad hoc signed retry passed. Cross-process UserDefaults
  tests require permission to write their test suites; sandbox-only runs cannot
  establish interprocess persistence.

## Limits and recovery

Only a device without a debugger attached can establish that 0xdead10cc is gone.
Acceptance: inside and outside a schedule window, perform 20 open/lock/unlock
cycles, lock within 1–2 seconds of recovery, and include a foreground wait over
30 seconds. Check analytics for new Tyri 0xdead10cc reports. Recheck shielding,
break expiry, usage lock expiry and release of expired temporary sessions.

This patch addresses the reported recovery/ManagedSettings lock chain. Existing
interactive schedule registration and break-start paths still make synchronous
DeviceActivity calls under their state transaction; those distinct paths remain
a suspension/stall risk and are not claimed fixed by these simulator results.
No merge, TestFlight upload or device acceptance was performed here.

Reverting code restores the old lock behavior. New `shieldIntent.v1.*` preference
keys are additive; identity, saved rules, monitor names and shared container stay
unchanged. Do not remove an active user's shared data to roll back.
