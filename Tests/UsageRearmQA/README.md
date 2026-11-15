# Usage rearm regression

Run `python3 Tests/UsageRearmQA/run.py`. To reproduce against the previous
production code while retaining the corrected native contract:

```sh
QA_REVISION=edd74e9fdfe54f0114fb3bb0ec27dd0371977456 python3 Tests/UsageRearmQA/run.py
```

Apple's [`stopMonitoring(_:)` contract](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/stopmonitoring(_:)) treats an empty argument as **stop all activities**. The former doubles treated it as a no-op, hiding the regression.

This suite compiles the production monitor extension, usage lifecycle, ownership
ledger and transaction code. A deterministic clock drives two 10-minute
allowance / 180-minute lock cycles. After actual threshold and expiry callbacks,
it requires the next allowance and an unrelated schedule to remain registered.
It also checks duplicate expiry/stale thresholds do not replace the healthy
allowance, and cleanup of an acknowledged inactive owner preserves independent
usage, lock, schedule and break registrations.

The native boundary is a double with Apple's documented empty-array semantics.
The suite verifies requested registrations and cleanup; it cannot prove real
Screen Time usage counting, callback delivery, or shield enforcement.
