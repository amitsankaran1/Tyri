# Follow-up to the Opus 5.5 adversarial review

Scope authorized by Amit: implement the concrete fixes recommended in Claude's review of merged `1bea72d` (PR #33). Original review and artifacts: `/tmp/tyri-opus-bugbash-review/REPORT.md`. This follow-up preserves existing product rules: additive-only active editing, fixed timed deadlines, explicit cooldown release, and one break per activation.

| Finding | Change | Regression seam |
| --- | --- | --- |
| Disconnect/re-register bypasses active tag blocks | Refuse disconnect and replacement at the configuration boundary while tag blocks are enabled or saved rules are unreadable; explain the restriction and confirm inactive disconnect | Simulator production tag callback and disconnect UI |
| Unreadable or missing lists clear active shields | Shared loaders distinguish failed decoding from empty data; undecodable nested selections fail their containing list; active enforcement preserves intent if a referenced list is missing | UnreadableStoreQA compiles production loaders, extension and actuator |
| Unreadable rules strand expired usage locks | Release timed ownership using persisted deadlines; retain independent manual ownership from its lock snapshot | UnreadableStoreQA; ForegroundRecoveryQA |
| Emergency Access cannot reach or clear unreadable owners | Error banner occupies its own safe area; hide misleading first-block setup; enumerate persisted enforcement owners for emergency release | MutationStateQA; corrupt-data simulator flow |
| Routine checking flashes failures | Keep healthy presentation during observation and Save; initial unconfirmed usage shows a neutral waiting state; initial-only progress banner | RecoveryPresentationQA and ForegroundRecoveryQA |
| Save while inactive defers work | Explicit Save opens a bounded effect-admission window even if the scene is inactive | ForegroundRecoveryQA |
| Interrupted break reports failure then starts | Pending registration feedback describes confirmation and the original deadline; clear stale feedback when the break is confirmed | Existing command-expiration worker simulation and source/UI review |
| Large-text countdown reflows; status contrast | One wrapping countdown Text and primary-color status title | Largest accessibility text simulator capture |
| Durations resemble clock times | Human duration units and an accessibility value | Simulator duration controls |
| Typing challenge has no mismatch feedback | Identify the first differing normalized character while retaining the exact-match submission guard | Simulator Emergency Access |
| Pending temporary session claims blocking | Home card and row distinguish awaiting confirmation, error and registered session | Simulator pending fixture |
| Three editor exits | Hide the redundant system back button; retain explicit Cancel and Save | Simulator detail capture |
| All-day schedule shows equal times | Plain “All day” summary | Schedule summary and simulator inspection |
| Diagnostics omit recovery state | Include temporary-session, break and pending-monitor state; qualify readback without authorization or targets | Simulator diagnostics |
| Deadline components lack time zone | Include the originating time zone for absolute one-shot deadlines | Native schedule construction and compilation |

## Evidence and interpretation

`UnreadableStoreQA` fails all three original preservation/expiry assertions on main and passes after the fix. The original review's “unreadable groups” payload actually decodes as a valid list with a different ID and no selection; the regression suite separately covers actual malformed JSON, nested selection corruption, and missing referenced lists.

The simulator fixtures use empty picker tokens and cannot establish real Screen Time enforcement. Tests of the tag callback replace the physical scan only. Hardware acceptance remains required for real usage thresholds and second cycles, shield enforcement, NFC, and suspension/RunningBoard behavior.

Wall-clock changes, the existing native activity ceiling, and residual preferences IPC under the short lease remain risks from the report, not newly reproduced defects. This change does not redesign those mechanisms or claim they are solved. A clock-policy change would alter product behavior; replacing preference synchronization needs a separate measured cross-process design.

Validation and independent review results will be recorded with the PR and existing Notion task after execution. No merge or TestFlight delivery is implied by this branch.
