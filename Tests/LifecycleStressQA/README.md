# Production ownership stress

`python3 Tests/LifecycleStressQA/run.py` compiles the unmodified production
`Shared/MonitorLedger.swift` under Swift 6 complete concurrency checking and runs
64 reproducible seeds, each with 1,000 transitions. It checks properties of the
production implementation rather than comparing it with a duplicate state model.

Coverage: same-input reservation preserves confirmed ownership; native failure
preserves confirmed ownership; stale native returns and callbacks cannot change
newer ownership; invalidation removes ownership; JSON round-trip retains all
state; observed orphan names are retired; cleanup cannot cause identity reuse.
Generated sequences include configuration ABA, early callbacks, late failures,
out-of-order returns, restart, cancellation, orphan discovery and cleanup.

Replay one sequence with `QA_SEED=37 QA_STEPS=1000 python3 Tests/LifecycleStressQA/run.py`.
On failure the runner deletes chunks of the sequence while the same invariant
still fails and prints a `QA_TRACE='[...]'` command for the minimized trace.
The operation sequence is deterministic; UUID values are intentionally opaque and
aren't used to decide transitions or compare runs.

The independent CallbackLifecycleStressQA suite covers callback/lock cycles.
This suite does not test actual UserDefaults durability, native Screen Time
registration/counting/shielding, physical suspension, or UI. Existing transaction,
store-durability, callback, native-boundary and simulator suites cover separate
parts of those boundaries; actual enforcement still needs a physical device.
