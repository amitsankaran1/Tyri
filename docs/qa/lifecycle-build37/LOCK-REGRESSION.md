# Unavailable shared storage: bounded audit defect

This is a demonstrated current-main defect, **not an established cause of the reported build37 reopen symptom**.

`EnforcementTransaction.beginEffect()` treated every failed nonblocking acquisition as transient contention. Missing or unwritable shared storage therefore retried forever while effects remained enabled. `BlockingActuator.effectLease()` had a separate equivalent loop. Neither loop held a file lock while waiting, but a permanent storage error could stall its effect worker indefinitely.

The fix exposes the acquisition result's contention distinction to both effect callers. Real local-mutex or file-lock contention still retries; missing container/open failures and non-contention flock failures fail closed immediately. No enforcement state is disabled, no unlocked write is permitted, and durable shield intent remains available for a later recovery retry. Existing lifecycle admission locks remain in place.

## Tests and observed results

All tests use uniquely named temporary UserDefaults suites and temporary lock paths. No real App Group or user configuration is touched.

- **RED observed:** `QA_REVISION=a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698 python3 Tests/UnavailableTransactionQA/run.py` compiled actual baseline transaction source and timed out after three seconds in the missing-parent-directory case. The isolated subprocess was terminated by the test runner.
- **GREEN observed before adding the actuator case:** `python3 Tests/UnavailableTransactionQA/run.py` passed unavailable storage/repair, real cross-process flock contention/retry, and lifecycle-disable-during-contention cases against the changed transaction source.
- **Existing regression passed:** `python3 Tests/TransactionQA/run.py` retained all 320 updates from eight processes performing 40 nested transitions each; process exit released its lease.
- **Actuator case added, final rerun pending:** compile actual production actuator with existing ShieldQA native doubles; persist intent, make the lock path unavailable before running deferred effects, require no native writes, restore storage, require pending-intent replay and zero native IPC while holding the lease. `QA_ACTUATOR_REVISION=a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698` selects the old actuator while keeping the repaired transaction, isolating the second loop's baseline failure.
- Expanded suite compilation encountered `No space left on device`. Earlier sandbox runs also failed to find a writable temporary directory; host-context execution produced the observed transaction red/green results above. Final current-source verification must be rerun serially after resource pressure is resolved; this document does not claim an actuator pass yet.

Final commands (all required to close this finding):

```sh
QA_ACTUATOR_REVISION=a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698 python3 Tests/UnavailableTransactionQA/run.py
python3 Tests/UnavailableTransactionQA/run.py
python3 Tests/TransactionQA/run.py
python3 Tests/ShieldQA/run.py
python3 Tests/ForegroundRecoveryQA/run.py
```

The first command should reproduce the baseline actuator timeout; the other commands must pass. The main `scripts/check.sh` discovers the new suite automatically. Production `begin(wait:)` uses an explicit return so the existing ForegroundRecoveryQA lease probe can continue instrumenting that public boundary without changing the test assertions.
