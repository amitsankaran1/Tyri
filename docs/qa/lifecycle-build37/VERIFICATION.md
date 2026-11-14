# Verification ledger

Baseline: a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698 (current main; build37 source unverified).

- Original recurrence: not reproduced. No device counting or shielding acceptance.
- Initial `bash scripts/check.sh`: progressed through recovery/migration tests, stopped on default compiler module-cache sandbox denial in MonitorLedgerQA. Not a full pass.
- Rerun with writable cache: callback QA 903 checks and callback stress 2767 transitions passed; stopped on disk exhaustion compiling recovery. Not a full pass.
- New ledger stress: 64 seeds × 1000 production-ledger transitions passed; replay/minimization supported.
- New callback stress: 100 complete 10/180 cycles / 2767 transitions passed with deterministic clock/native doubles.
- Unavailable lock regression: baseline production beginEffect times out after 3 seconds; bounded fix passed unavailable/repaired storage, cross-process contention and cancellation tests. Expanded actuator test pending final run.
- Baseline Xcode simulator test/analyze: running on isolated iPhone17Pro iOS26.5, result /private/tmp/tyri-lifecycle-baseline.xcresult; log /private/tmp/tyri-lifecycle-xcode-baseline.log. This binary was compiled before edits.
- Final revision checks: pending; do not treat earlier results as final revision validation.

Environment issues: Mac free space reached ~123MB; temporary compile failures are recorded, not masked. Initial shell networking/Rex socket and compiler-cache access required normal host escalation. No unrelated files or simulator data were removed.
