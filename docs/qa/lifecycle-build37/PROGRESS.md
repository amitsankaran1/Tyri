# Build 37 blocking lifecycle

Phase: establish source and reproduce (2026-11-14).
Workspace: /private/tmp/tyri-lifecycle-37
Branch: fix/lifecycle-build37; baseline a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698.
Rex: tyri-blocking-lifecycle (session:01a1dc14-f03b-7910-944c-5c1465403ba4).

Evidence: original checkout is deferred 9bf604c, not build 37. Remote has no open PRs. Prior fix is merged; prior task claim is being reconciled, not replaced.
Reported: reopen -> subsequent ten minutes -> block. Exact reopen time/target/preceding transition unknown. Registration 17:43:52Z, threshold 21:43:21Z, lock start 21:43:22Z, settings readback 21:47:45Z do not prove counting start or effective shielding.

Hypotheses: native monitor registration/delivery behavior; interrupted Save/recovery; allowance rearm after expiry; callback/publication races. No cause declared.
Workers: root integration/Xcode; release_audit provenance; lifecycle_investigation production trace; stress_audit deterministic tests and edge cases.
Tests: deterministic baseline running; Xcode pending; physical device unavailable (paired iPhone Duo).
Next: reconcile exact build source and claims, reproduce bounded defects, add production regression tests, independent standards/spec review.
Boundaries: no merge/distribution, no real restrictions/data reset, healthy counter retained.
Resume: read this note and logs in /private/tmp/tyri-lifecycle-*.log; inspect git status here before editing. Do not use the original deferred checkout.

Milestone 17:07 ET: build37 provenance blocked by Apple agreement. See PROVENANCE.md. Current-main callback stress passed 100 cycles/2767 transitions; ledger stress passed 64,000 operations. No recurrence cause reproduced. Added bounded diagnostics for app vs expiry registration, generation publication, native request/return times and foreground correlation without changing healthy monitor policy. Unavailable-storage effect retry loop is under targeted reproduction/fix. Baseline UI tests running; first six including blank-name Save and diagnostics passed on iOS26.5. Full deterministic rerun blocked by disk full; initial failure was sandbox cache denial. Mac ~130MB free. No user data deleted.

17:10 ET: storage loop reproduced on baseline a9c2225 (3-second timeout). Transaction acquisition now distinguishes true contention from unavailable storage; same classification added to shield actuator after independent spec review. Registration request/return timestamps are captured around native work, then recorded under the state lease; interrupted pre-commit results remain inherently absent. UI suite continues on baseline; later compilation attempts failed due disk space, not weakened checks. Final revision/checks/review still pending.
