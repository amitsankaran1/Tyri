# Tyri state machines, invariants, and reachable defects

Updated 2026-11-06. Canonical audit for native Tyri, starting at `dcab8bf` (released 2.4 (4) source: `e9bcf4b`). This file contains the inventory, transition tables, grouped issues, reproduction evidence, fixes, and verification. Deferred AI/NL work on `develop/2.4` is outside this audit. Existing manual activation remains indefinite; a duration choice is deferred by product decision.

## Interpretation and scope

“Active” means a logical owner exists; it does **not** prove that iOS is shielding an app. Rule configuration, activation ownership, monitor registration, effective settings, authorization, and presentation are separate machines. Treating them as one Boolean caused several defects below.

Production entry points reviewed: app launch/foreground/timers; all monitor callbacks; rule/list save and delete; break/cooldown actions; temporary-session actions; tag reader delegates; authorization; migration; emergency override. DEBUG fixtures and simulation controls are test inputs, not production activation paths. Native navigation, picker drafts, and validation are included where they affect saved state.

Evidence labels:

- **Reproduced**: production code or an extracted unchanged production method fails a deterministic test on `dcab8bf`, then passes with the fix. OS calls use doubles unless stated otherwise.
- **Reachable interleaving**: an app operation and extension callback can overlap at the named boundary. A deterministic hook forces that ordering; it is not a measurement of its frequency on a phone.
- **Defensive check**: a helper rejects an invalid direct request, but a complete production path to that request has not been demonstrated. Not counted as a confirmed user bug.
- **Unverified**: platform behavior, physical enforcement, or an input that ordinary app code has not been shown to produce. Not counted as a confirmed bug.

## Global ownership and safety contract

For each rule, define `M = isEnabled`, `S = current calendar window exists and has not been released`, `U = future usageLockEnd`, `B = future breakEnd`. Intended protection is `(M || S || U) && !B`. Timer rules never offer breaks. Different rules and temporary sessions own different named stores; releasing one owner must not clear another owner. Permission and write errors can prevent intended protection from becoming effective protection.

`running` is a reconciled projection, not calendar truth. Activity callback order is not time. A monitor's presence is registration evidence, not proof that callbacks will arrive. Cooldown expiry makes release *available*; it never releases automatically. Break and lock expiry are automatic.

All enforcement transitions now acquire `EnforcementTransaction`: a recursive process mutex plus an App Group `flock` lease, with preferences synchronization at the outer boundary. This serializes foreground and extension decisions and their side effects. No `await` is allowed inside a lease. Nested helper calls share the lease. Failure to obtain it performs no mutation. OS process exit releases it. This is mutual exclusion, **not** a crash-atomic transaction spanning UserDefaults, DeviceActivity, and ManagedSettings. Recovery still reconciles interrupted side effects.

Apple documents that callbacks may begin as soon as registration starts: [DeviceActivityCenter.startMonitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)). This is why registration and callback ownership cannot be treated as sequential by assumption.

Source: [EnforcementTransaction](../Shared/EnforcementTransaction.swift), [ScreenTimeManager](../Tyri/Services/ScreenTimeManager.swift), [monitor callbacks](../TyriMonitor/TyriMonitorExtension.swift).

## Prioritized grouped issues

All fixes below are implemented in this checkout. Verification status is maintained at the end of the file. P1 = protection can be bypassed/lost, unwanted blocking can persist, or saved configuration can be duplicated/lost. P2 = erroneous/duplicate user action or misleading state.

| Issue | Priority / impact | Confirmed reachable failure on baseline | Fix / regression evidence |
|---|---|---|---|
| **SM-01: Serialize lifecycle ownership** | P1: orphan shields; allowance reset during overlapping recovery | Temporary start saves session → registration overlaps finish → start applies shield after session is gone. Expiry clears deadline → overlapping recovery arms allowance → original expiry arms a second generation. App and extension had no shared exclusion. | Shared lease around transition boundaries; identity recheck after registration; expiry arms only if absent. `StateMachineQA` forces both interleavings. `TransactionQA` tests actual separate processes, recursion, preferences visibility, process exit. |
| **SM-02: Commit deletion and refresh dependent monitors** | P1: removed apps keep counting; deleted rule can be revived | `AppGroupEditorView.deleteGroup` changed references but never replaced the old DeviceActivity event. Last-list deletion left its monitor alive. `deleteBlock` stopped monitors before its debounced removal became visible to callbacks. | Flush detached references and lists, replace affected timer monitors (empty target stops them); publish rule deletion before teardown. `MutationStateQA` tests remaining-list, last-list, persisted visibility, and callback boundary. |
| **SM-03: Complete recovery and release transitions** | P1: lost automatic end/re-lock; timer no longer counts | Emergency override stopped a consumed lock without rearming usage and returned before manual-off persistence. Temporary-session reconcile reapplied shields without repairing lost expiry. Break restore resumed the countdown without repairing a lost monitor. Stale break action could execute after ownership ended. Launch could arm an allowance before reconciling an expired persisted lock, then arm again. Replacement at 20 activities retried forever without freeing the old allowance slot. | Persist release before side effects; rearm absent timers while preserving healthy ones; repair expiry with original deadline and short-window warning; failed break repair resumes protection; check break ownership at execution; reconcile any persisted timer deadline first; free an old allowance slot when replacement reaches capacity. `MutationStateQA`, `StateMachineQA`, `UsageRecoveryQA`. Temporary-session enforcement errors are now visible. |
| **SM-04: Bind NFC completion to its reader session** | P2 (can undo intended protection): duplicate toggle / canceled scan still acts | Start could replace a live reader; an old invalidation changed the newer reader's state; duplicate connect completions each called `onTagScanned`; a canceled reader's delayed completion still toggled. These are actual asynchronous delegate entry points. | Reject repeated Start; compare reader identity; consume session before dispatching the callback; ignore stale/canceled completions. `NFCStateQA`: four failures before, four passes after. |
| **SM-05: Make migration retryable and preserve ownership** | P1: duplicate lists/rules or silent release on upgrade | Migration assigned random IDs and appended. Kill between group write, block write, and completion marker → retry duplicates. Legacy `isEnabled` was not decoded. Decode failure still marked migration complete and removed source. | Stable namespaced IDs and insert-if-missing; preserve enabled state; decode before mutation; retain unreadable input; move teardown after replacement persistence. `MigrationStateQA`: four failures before, four passes after. Corrupt-input check is defensive; interrupted valid writes and loss of legacy enabled state are confirmed paths. |
| **SM-06: Derive edit protection from calendar ownership** | P1: weakening/deletion before a delayed start callback; P2: expired rule stays edit-locked | `isBlockActive` trusted `running`. During a current window with delayed callback it returned false, allowing edit/delete guards to pass; after a missed end it returned true indefinitely until reconciliation. | Compute current window and release marker directly; retain independent manual/usage ownership. `MutationStateQA`: both boundary failures reproduced and fixed. |

### SM-07: Actionable enforcement warnings (follow-up, 2.4 (7))

**P2, confirmed presentation gap.** User reports a saved block saying “Needs attention” without instructions. In 2.4 (6), `HomeView.overview` gave a generic instruction to open a block, and `BlockEditorView` only offered a dedicated recovery action for schedule-registration errors. Usage/shield warnings could show raw detail with no recovery button; schedule and lock-end errors were split into separate Home banners.

Fix: a named attention section near the top of Focus; explicit “View recovery steps” affordance; a “What to do” section in block details with cause-specific instructions, direct list navigation, Retry blocking, Screen Time settings and diagnostics. Schedule/lock-end/usage errors participate in the same presentation. The shared retry service uses `forceReset: false`, so a healthy allowance survives retry. Temporary-session errors also appear in the Focus overview. Existing active-block edit protections are unchanged.

Evidence: `Tests/RecoveryActionQA/run.py` passes five production retry contracts (preserve allowance, denied permission, stale/deleted rule, schedule repair, tag isolation). Eight production presentation checks also pass (permission precedence, active shield/usage/end errors with empty-message fallbacks, schedule errors, break state, missing monitor). All five blocking UI flows pass on the iPhone 15 Pro / iOS 26.5 simulator; attention, recovery and linked-list screenshots were visually inspected, with the first two recorded in Notion. The added iOS 27 retry/permission-navigation check initially failed: UIKit logged competing presentation attempts when `.sheet` was attached to the recovery Section. Moved sheet state and presentation to the stable BlockEditorView host; the exact regression now passes (1/1, 24.0 seconds), reaching Allow Screen Time access after Retry. This was caught during implementation, before release. This fixes the recovery UI, not an unobserved physical-device failure; the exact error on the user's phone has not yet been supplied.

Recovery invariants: warnings expose an actionable next step; an empty error string still produces explanatory text; retry reads the current saved rule under the enforcement lease; deleted rules and denied authorization do not mutate enforcement; retry cannot reset a healthy usage allowance. A retry attempt does not assert success: status is re-read from persisted/OS state.

| State / trigger | Guard / transition | Next presentation |
|---|---|---|
| Missing permission → open recovery | Open Settings; grant occurs through system authorization | Remains setup until authorization is approved |
| Error or missing monitor → open block | Read saved lists and actual tokens | Cause-specific instructions and recovery actions |
| Retry → current timer rule | Approved + lease acquired; apply with `forceReset: false` | Re-read actual status; warning remains if repair failed |
| Retry → current schedule rule | Approved + lease acquired; register schedule and reconcile | Re-read actual status |
| Retry → deleted rule / denied permission / unavailable lease | Reject mutation | Settings opens; no false success claim |
| Edit list → save → return | Existing active-edit guards still apply | Updated selection and recovery state |

Related fixes remain grouped rather than filing one issue per failed assertion. Duplicate direct calls to `startBreak` are also rejected, but the public manager already checked the allowance; those two tests are defensive hardening, not separate confirmed user bugs.

## Machine 1: Saved rule and manual activation

Source: [BlockRule](../Shared/BlockRule.swift), [BlockStore](../Tyri/Services/BlockStore.swift), [BlockEditorView](../Tyri/Views/BlockEditorView.swift).

States: unsaved draft; saved schedule/timer/tag configuration; manual off/on; logically active from any owner; deleted. These are orthogonal dimensions, not one enum.

Invariants: a draft does not become a saved rule until Save; active rules accept only strengthening changes; `isEnabled` means manual/tag ownership, **not** whether a schedule or timer is configured. Each manual change invalidates the previous cooldown identity. No-op timer Save preserves the usage generation. Save checks authorization and nonempty targets for manual activation.

| From / event | Guard | To / effects |
|---|---|---|
| New draft → Cancel | — | Discard draft; no registration |
| Draft/existing → Save | Valid; if active, preserve type/timing/friction and union list IDs | Persist and flush, apply manual owner, register changed timing |
| Manual off → Save with Block now | Permission approved, targets nonempty | Manual on, new activation identity; indefinite until explicit release |
| Manual on → attempt weaker edit | Any owner active | Preserve protected fields; no release |
| Inactive → Delete | Recheck canonical ownership under lease | Publish absence, stop schedule/usage/break, clear this rule's stores |
| Saved timer → rename/no-op Save | Monitor healthy, timer inputs unchanged | Preserve current allowance |
| Configured timer → valid target/limit change | Not currently locked | New generation; old activity removed after registration succeeds |

Invalid transitions corrected: SM-02 deletion visibility; SM-06 stale activity gate. An empty schedule/list configuration is allowed as incomplete setup; it must not be represented as successful enforcement.

## Machine 2: Calendar activation and release

Source: [BlockingSchedule](../Shared/BlockingSchedule.swift), [ScheduleEnforcement](../Shared/ScheduleEnforcement.swift), [SchedulingManager](../Tyri/Services/SchedulingManager.swift).

States: no schedule; outside selected window; inside unreleased window; released for this window; paused within a window. `scheduleWindowStart` identifies the activation; `scheduleReleasedUntil` suppresses the current window. Weekday means the day the window **starts**, including overnight windows. End is exclusive. Equal start/end is a full-day window.

Invariants: callbacks only request reconciliation against current time; stale end cannot release a current window. A new window resets break allowance. Schedule end preserves manual ownership. Early release does not disable future windows.

| Event | Transition / effects |
|---|---|
| Start/end callback, foreground, 30s refresh | Recompute window; never infer ownership from callback kind |
| Enter new selected window | Set window identity/running; reset break allowance; apply unless paused |
| Reconcile same window | Preserve break/release; idempotently restore intended shield |
| Complete early release | Mark released through window end; clear current ownership |
| Window ends | Clear schedule projection/break; preserve manual shield if enabled |
| Next window begins after release | Expired release marker removed; fresh activation |
| Save schedule/register fails | Configuration retained; error shown; current window still reconciled |

Tests: calendar DST/overnight/end-boundary suite; ownership suite; scheduling registration failures/retries; SM-06 canonical edit gate. `repeats=false` has no current editor path; legacy/import semantics are an unverified compatibility edge, not a newly confirmed UI defect.

## Machine 3: Usage allowance and timed lockout

Source: [UsageMonitoring](../Shared/UsageMonitoring.swift), [UsageLimitManager](../Tyri/Services/UsageLimitManager.swift), [TyriMonitorExtension](../TyriMonitor/TyriMonitorExtension.swift).

States: not measurable/off; allowance registered with generation G; registration failed; locked until E; locked with expiry registration failure; expired awaiting reconciliation; rearming. Registration and ownership are separate dimensions.

Invariants: at most one *current* allowance generation; a live lock owns the cycle; a stale generation cannot consume a new allowance; duplicate threshold cannot extend E; failed replacement preserves old generation/monitor when a free activity slot exists; release clears deadline before stopping its activity; manual owner survives lock expiry. Typed domains alone cannot measure usage.

| From / event | Guard | To / effects |
|---|---|---|
| Missing allowance → launch/foreground/retry | Valid measurable targets; no persisted lock to reconcile | Register new G, optional progress events; fallback to limit-only |
| Healthy allowance → foreground/no-op Save | No changed inputs/error | Same G and counter |
| Allowance G → threshold | Current G, registered activity, timer type, positive limit | Persist E, shield, release consumed activity slot, register expiry |
| Locked → duplicate/stale callback | E still future | Same E; repair missing expiry; keep shield |
| Locked → warning/end/foreground | E has passed | Clear deadline/lock monitor; release usage owner; arm once if absent |
| Locked → explicit early/emergency release | Authorized release flow | Clear lock; arm fresh allowance; clear manual owner where requested |
| Register replacement fails | — | Restore old G, retain old monitor when capacity permits, expose usage error |
| Replace at 20-activity capacity | Old allowance occupies a slot | Retire old allowance first, then register new G; failure is explicit and retriable, not an endless capacity failure |
| Empty/non-timer selection | — | Stop obsolete allowance; timer reports no measurable targets |
| Old generation/removed rule callback | Identity/type/registration check fails | No mutation |

Known pre-existing 20-activity issue was fixed in 2.4 (4): consumed allowance is stopped before registering lock expiry. This audit adds overlapping recovery and persisted-expired-lock handling. All-day schedule ends at 23:59:59; actual iOS midnight delivery remains device-dependent.

## Machine 4: Usage progress projection

Source: [UsageProgress](../Shared/UsageProgress.swift).

States: unknown; current-generation same-day milestone; next-day zero; stale-generation unreadable. Invariant: progress is a lower bound from callbacks, never elapsed wall time; monotonic within generation/day; at most 60 milestones plus enforcement event.

| Event | Result |
|---|---|
| New allowance with progress registration | Record 0 tagged with new G |
| Progress callback | Accept valid milestone for current G; max(previous, received) |
| Old/out-of-order progress | Old G ignored; smaller same-G value cannot regress |
| Local day changes | Display 0 until a new milestone |
| Progress-event registration rejected | Enforce with limit-only; display unknown |

No additional confirmed defect. Record writes from the callback and registration paths are inside the shared lease.

## Machine 5: Break allowance and timed pause

Source: [BreakMonitoring](../Shared/BreakMonitoring.swift), [BreakManager](../Tyri/Services/BreakManager.swift), [BreakView](../Tyri/Views/BreakView.swift).

States: unavailable; available for this activation; registration pending; paused until E (used); finished/used; canceled by owner ending. Manager displays one break at a time; persisted per-rule deadline is authoritative.

Invariants: timer lockouts cannot take breaks; a pause requires an existing owner; register automatic re-lock before lifting shields; one allowance per activation; no extension on repeated request; a stale finish cannot re-enable a released owner.

| Event | Guard | Result |
|---|---|---|
| Take break | Non-timer, owner still active, break enabled/unused, no other local break | Register expiry then persist E/used and clear own shields |
| Registration fails | — | Keep protection; return failure |
| Early end callback | E still future | Do not end break |
| Deadline / End break now | Current pause exists | Clear pause; reapply only surviving owners; used stays true |
| Relaunch/foreground while paused | E future, monitor absent | Repair using original E; if repair fails, end pause and resume protection |
| Window/tag/manual session ends | — | Cancel pause without reapplying obsolete owner |
| New activation | — | Clear used marker |

SM-03 covers stale execution and lost re-lock recovery. Direct duplicate helper requests are defensively rejected; manager-level eligibility was already present.

## Machine 6: Cooldown / explicit early release

Source: [CooldownManager](../Tyri/Services/CooldownManager.swift), [CooldownView](../Tyri/Views/CooldownView.swift).

States: none; waiting until E for activation identity A; ready for A; canceled/stale. A is the combined manual UUID, schedule-window start, and usage deadline of current owners.

Invariants: no automatic release at countdown completion; zero-minute setting offers no early-release path; completion must still match A; closing the sheet cancels its wait; a new activation cannot reuse an old wait.

| Event | Transition |
|---|---|
| Request stop early | Positive minutes + active identity → waiting; cancel another local wait |
| Timer reaches E | Waiting → ready; protection unchanged |
| Reopen app | Restore waiting/ready only if identity still matches |
| Tap Stop blocking | E elapsed + A matches → release current schedule window, usage lock and manual owner; preserve future automation |
| Identity changed | Cancel stale wait; do not release |
| Cancel/dismiss sheet | Clear wait/identity; leave protection |

The release boundary is now serialized with extension transitions (SM-01). No new independent cooldown defect was reproduced.

## Machine 7: Temporary session

Source: [AdHocMonitoring](../Shared/AdHocMonitoring.swift), [AdHocManager](../Tyri/Services/AdHocManager.swift), [AdHocBlockView](../Tyri/Views/AdHocBlockView.swift).

States: none; starting; active(id, snapshot, E); release waiting(R); release ready; recovery error; finished. The list is snapshotted, so later edits/deletion do not weaken it.

Invariants: only one session; 15–1440 minutes; nonempty targets; background expiry registration must succeed before initial shielding; finish acts only on matching ID; deadline repair cannot extend duration; waiting five minutes does not itself release. Error state must not claim successful protection.

| Event | Transition |
|---|---|
| Start | Reconcile old expiry, validate, persist snapshot, register; on failure roll back matching ID |
| Registration returns after cancellation | Identity mismatch → no shield write |
| Foreground/callback before E | Preserve ID/deadline; restore shield and missing expiry monitor |
| Repair with <15 minutes left | Register 15-minute window with warning at original E |
| Expiry registration repair fails | Preserve session/intent; expose error; opening at E still completes |
| Request early release | Persist R=now+5m once |
| Release tap before R | No-op |
| Release tap after R or deadline E | Remove session before stop/clear; independent rule stores untouched |
| Stale callback for old session | Reconcile current session by current time; never blindly clear |

SM-01/03 fix orphan/recovery failures. A repair error may require opening Tyri at the deadline if iOS refuses registration; the UI now reports that limitation.

## Machine 8: Authorization and effective protection

Source: [ScreenTimeManager](../Tyri/Services/ScreenTimeManager.swift), [SettingsView](../Tyri/Views/SettingsView.swift).

States: not determined; request pending; approved; denied/revoked. Logical sessions survive permission changes; permission is not an activation owner.

| Event | Result |
|---|---|
| Request access | Await system authorization; refresh status |
| Approved transition | Reapply manually enabled rules; foreground repairs schedules/usage |
| Denial/revocation observed | Setup presentation; manual start rejected; preserve saved rules |
| Regrant | Restore intended protection without granting healthy timers a fresh allowance |

Invariant: UI must distinguish intended activity from permission to enforce. `isBlockActive` intentionally protects active configuration even if permission is lost. Real revocation/regrant and token validity require device acceptance; simulator fixtures are not evidence of enforcement.

## Machine 9: Registration and shield materialization

Source: [SchedulingManager](../Tyri/Services/SchedulingManager.swift), [BlockingActuator](../Shared/BlockingActuator.swift), [EnforcementDiagnostics](../Shared/EnforcementDiagnostics.swift).

Registration states: absent; requested; registered; failed; obsolete/stopping. Shield states: clear; write requested; readback matched; readback mismatch; empty target; truncated selection. A matched readback is not a verified shield.

| Event | Result / invariant |
|---|---|
| Apply targets | Write all properties; categories separate; app/domain chunks ≤50; clear old surplus chunks |
| Shrink selection | Old extra stores cleared; no stale targets |
| >400 apps/domain tokens | Bounded truncation + explicit error, never full-success claim |
| Empty targets | Explicit error |
| Settings readback differs | Record error and diagnostic |
| Clear one owner | Only that owner's chunks/category store cleared |
| Registration missing/failed | Foreground retries with original ownership/deadline; healthy allowance preserved |
| Progress registration fails | Retry enforcement-only event |

Independent owner and 50-token chunk boundary suites pass. Global 50-store capacity across many rule IDs is **unverified**, not solved by the per-rule eight-chunk cap. Physical selection/token expiry and actual shield interaction remain device tests.

## Machine 10: Lists, reference integrity, persistence

Source: [AppGroupStore](../Tyri/Services/AppGroupStore.swift), [AppGroupEditorView](../Tyri/Views/AppGroupEditorView.swift), [BlockResolution](../Shared/BlockResolution.swift).

States: draft; saved; dirty/debounced; flushed; referenced by inactive rules; referenced by active rules; deleted; decode unavailable.

Invariants: only additive changes while any referencing rule is active; save compares against current stored group, not stale draft; referenced selections resolve by union; changed measurable tokens replace usage events; rename/typed-domain-only edit preserves usage counter. Temporary sessions retain snapshots.

| Event | Transition |
|---|---|
| Draft Cancel | Discard |
| Save list | Validate pending domain; enforce additive constraint; persist/flush; refresh dependent shields |
| Measured tokens change | Replace affected timer monitor unless lock owns cycle |
| Rename / typed-domain change | Refresh shields if active; preserve usage allowance |
| Delete while referenced active | Reject |
| Delete while inactive | Detach references and flush both stores, replace/stop affected usage monitors |
| Decode failure | Existing code falls back to empty collection/selection; no proven ordinary input path to corruption in this audit |

SM-02 fixes deletion synchronization. Corrupt list decoding is a risk to address with recovery UX if encountered; it is not mislabeled as a naturally reachable confirmed bug here.

## Machine 11: Migration

Source: [Migration](../Tyri/Services/Migration.swift).

States: legacy pending; decoded; groups written; blocks written; replacement enforcement applied; legacy teardown; complete; unreadable input pending.

Invariants: retries reuse IDs; never duplicate records; don't clear unreadable source; preserve legacy enabled ownership; completion marker follows replacement persistence. Stable IDs are derived from migration namespace, kind and source ID. Existing records with those IDs are not overwritten on retry.

| Event / interruption cut | Recovery |
|---|---|
| No complete marker + valid legacy data | Decode before mutation; insert missing groups/rules |
| Kill after groups, before blocks | Retry fills missing rules without duplicating groups |
| Kill after both, before marker | Retry inserts nothing; finish teardown/marker |
| Malformed legacy bytes/selection | Return pending; keep source bytes |
| Complete marker present | No-op |

SM-05 reproduces both interruption cuts and lost enabled ownership. Tests model exact persisted cuts, not arbitrary memory corruption.

## Machine 12: NFC reader and tag toggles

Source: [NFCManager](../Tyri/Services/NFCManager.swift), [TagRegistrationView](../Tyri/Views/TagRegistrationView.swift).

States: idle; scanning(session ID); connecting(session ID); completed/consumed; canceled; invalidated/error. Tag registration is separately absent/present; tag rules are all-off or one-or-more-on.

| Event | Guard / transition |
|---|---|
| Start | NFC available and idle → create one reader |
| Start while scanning | No-op |
| Detect + connect success | Current reader still owns scan → consume reader, deliver exactly one tag callback |
| Connect failure | Invalidate that reader; current invalidation reports error |
| Cancel | Clear ownership before invalidating |
| Old invalidation / delayed completion | Ignore unless matching current reader |
| Unregistered matching flow | Save first tag identifier |
| Registered correct tag | If any tag rule on, all off; otherwise all on. Flush ownership before shield effects |
| Wrong tag | No toggle |

SM-04 covers asynchronous session identity. Physical NFC discovery and connection behavior are not simulated by the regression mocks.

## Machine 13: Emergency override

Source: [TypingChallengeView](../Tyri/Views/TypingChallengeView.swift), `ScreenTimeManager.disableAllBlocks`.

States: challenge empty/incorrect/correct; releasing; current owners released. Case/whitespace normalization determines correctness; submit rechecks it.

| Event | Result |
|---|---|
| Incorrect/cancel | No enforcement change |
| Correct submit | Finish temporary session; release current schedule windows; persist manual-off; cancel breaks/locks; clear own stores; rearm absent usage allowances; cancel cooldown |
| Later scheduled window / new usage threshold | Normal automation may activate again |

Invariant: an emergency release must not silently disable future configured usage monitoring. SM-03 fixes that gap and the persistence ordering.

## Machine 14: Editor drafts, validation, navigation and presentation

Sources: [BlockEditorView](../Tyri/Views/BlockEditorView.swift), [AppGroupEditorView](../Tyri/Views/AppGroupEditorView.swift), [ScheduleEditorView](../Tyri/Views/ScheduleEditorView.swift), [UsageDurationPicker](../Tyri/Views/UsageDurationPicker.swift), [BlockStatusView](../Tyri/Views/BlockStatusView.swift), [HomeView](../Tyri/Views/HomeView.swift).

Draft states: unhydrated → hydrated local draft → dirty → validation failure or committed → dismissed. Schedule/duration sheet choices remain draft until their confirmation; parent Cancel discards. Selection navigation and creation sheet are separate optionals; selected IDs are cleared when removed. NavigationSplitView preserves the editor as layout adapts.

Presentation enum: `setup`, `paused`, `unavailable`, `blocking`, `tracking`, `off`. Precedence: missing permission → setup; break → paused; active owner with shield error → unavailable; active owner → blocking; timer error/missing monitor → unavailable; registered timer → tracking; otherwise off. Home groups rules by this projection. Temporary session has its own projection and now exposes enforcement failure.

| Event | Result / invariant |
|---|---|
| Appear once | Hydrate draft once; don't overwrite edits on refresh |
| Activity changes while editing | Save/delete rechecks authoritative ownership, not disabled control appearance |
| Validation fails | Keep draft; explain missing permission/targets; no partial activation |
| Save succeeds | Commit before monitor effects; dismiss unless schedule registration error needs attention |
| Timer ticks / callbacks / foreground | Recompute status; don't estimate usage from elapsed time |
| Device layout changes | Keep same navigation tree and reachable Save action |

No new navigation defect reproduced. Explicit bottom Save from 2.4 (4) remains. UI screenshots and test results are recorded below; presentation fixtures do not imply effective blocking.

## Machine 15: Launch, foreground and reconciliation

Sources: [TyriApp](../Tyri/TyriApp.swift), [HomeView](../Tyri/Views/HomeView.swift), service initialization and periodic refresh timers.

States: cold; initializing stores/authorization; migrating; restoring registrations/owners; foreground; inactive/background; resumed. These phases are implicit in `.task`, `scenePhase`, service initialization and timers. The runtime records survive process exit; local observable managers are projections rebuilt at launch.

| Event | Transition / invariant |
|---|---|
| Cold launch | Migrate legacy defaults; load stores; run guarded migration; reload migrated collections |
| Startup restoration | Reapply schedules, recover usage, reconcile locks/session, restore cooldown/break; preserve valid ownership identities |
| Foreground entry | Restore break/session, refresh authorization/manual shields, reconcile usage deadlines, repair missing schedule/usage registration when authorized |
| Foreground status tick | Recompute presentation and temporary-session expiry; never invent usage progress |
| Service 30-second tick | Reconcile calendar ownership / expired usage locks |
| Background/suspension | DeviceActivity extension owns background callbacks; foreground timers are not an expiry guarantee |
| Relaunch after interruption | Repeat recovery from persisted facts; healthy allowance must not reset and stale cooldown must not release a newer activation |

SM-03 fixes expired-lock ordering and missing expiry repair. The signed native UI runs exercise initialization and the existing launch assertion harness. There is no claim that background timer execution substitutes for a registered extension callback.

## Verification ledger and reproducible commands

Use this checkout as cwd. `QA_REVISION=dcab8bf` runs new regression cases against baseline production code where supported. Test doubles replace unavailable Apple frameworks, not the production transition bodies.

| Suite | Baseline evidence | Current result |
|---|---|---|
| `python3 Tests/StateMachineQA/run.py` | Shipped baseline: 2/13 pass (missing repair also fails the 2 precision assertions); pre-precision candidate: 11/13 pass; includes 2 defensive helper checks | 13/13 pass |
| `python3 Tests/MutationStateQA/run.py` | 8 failures | 8/8 pass |
| `python3 Tests/NFCStateQA/run.py` | 4 failures | 4/4 pass |
| `python3 Tests/MigrationStateQA/run.py` | 4 failures | 4/4 pass |
| `python3 Tests/TransactionQA/run.py` | New concurrency mechanism | 8 real processes ×40 nested transitions: 320/320 updates retained; exit without finish releases lease |
| Existing CallbackQA | Prior release baseline retained | 895/895 pass on final lifecycle code |
| Existing ActivationQA / UsageRecoveryQA | Prior release baseline retained | 7/7 and 7/7 pass |
| Existing SchedulingQA / ShieldQA | Prior release baseline retained | 10/10 and 16/16 pass |
| iOS SDK build | — | Debug simulator build, Release archive, distribution signatures/profiles and required entitlements verified |
| Native UI affected flows | — | iOS 27: 4/4 pass; iOS 26.5: 6/6 pass (including duration cancellation/persistence) |

TransactionQA must run with access to its isolated preferences domain; a filesystem-sandboxed subprocess run cannot establish cross-process preferences visibility. The first sandboxed attempt failed that environmental check; the unrestricted isolated-domain run passed. This is not counted as an app bug or hidden as a passing test.

Calendar/ownership commands (UTC is required for fixed test instants):

```sh
swiftc -module-cache-path /private/tmp/tyri-state-cache Shared/BlockingSchedule.swift Tests/ScheduleWindowTests.swift -o /private/tmp/tyri-calendar
TZ=UTC /private/tmp/tyri-calendar
swiftc -module-cache-path /private/tmp/tyri-state-cache Shared/BlockingSchedule.swift Shared/ScheduleEnforcement.swift Shared/EnforcementTransaction.swift Tests/ScheduleStateQA/Doubles.swift -o /private/tmp/tyri-ownership
TZ=UTC /private/tmp/tyri-ownership
```

## Remaining acceptance boundaries

No claim that simulator/logic tests resolve the reported physical iPhone incident. Required device checks remain: effective individual-app/mixed-category shielding; callback delivery across app kill/reboot; real revocation/regrant; token expiration; high aggregate store/activity pressure; extension runtime while a foreground transition is in progress. The App Group lock spans synchronous OS calls, so device validation must include contention and responsiveness. The lock is released by process death; it cannot make multiple Apple services crash-atomic.

iOS 17.5 previously timed out in both shipped-baseline and candidate XCTest runs; it is not passed. Previously passing modern OS runs are evidence for 2.4 (4), not automatically for this patch. 2.4 (6) is available in internal TestFlight; final source/signature/upload evidence is recorded below.

### UI test environment correction

An initial unsigned simulator build lacked App Group entitlements, so the transaction guard declined mutation and the existing launch assertion failed. This is retained as a failed run (`/private/tmp/tyri-state-ui.xcresult`). With normal simulator signing, all four affected flows pass on iOS 27 (`/private/tmp/tyri-state-signed-ui.xcresult`) and all six reliability/duration tests pass on iOS 26.5 (`/private/tmp/tyri-state-265-ui.xcresult`). This was not fixed by bypassing the guard or faking authorization.

Visual review caught ambiguous temporary-session copy: the error state now says “Session ends at” and explains that a session retains its original selection. It does not claim that failed protection is working during the early-release wait. The final copy passed its focused iOS 26.5 UI rerun and was visually inspected.

### Final precision regression and superseded package

Final review of new recovery code found a fractional-second issue: DateComponents drops subsecond time, but warningTime was rounded up from an unrounded repair start. The warning could arrive one second before the real deadline, be correctly ignored, and leave only the later 15-minute fallback. Two added production-code tests reproduced this in both temporary-session and break repair (`QA_REVISION=38da72b`: 11/13 pass; corrected source: 13/13 pass). Both now floor the repair start before constructing the schedule, matching usage-lock registration; all 13 lifecycle tests pass.

The 2.4 (5) upload process was interrupted and its package superseded. Build 2.4 (6) carries the precision fix; do not distribute the earlier package. The unchanged UI evidence remains valid. This is recorded as a defect caught during implementation, not a pre-existing shipped bug.

### Release package verification

Final production source: `8bb1ef551f303f3812a983c80f16a05395fc14fd` (base audit/fixes `38da72b33b9da00f6aac8bab2a3e6b5caa0c16a3`). Build: **2.4 (6)**. IPA SHA-256: `ae1551ba5c19d88b13167cf719aa8cd0de308f952f2d20acf4a474a0000f2beb`. App and extension distribution signatures and provisioning profiles verified; Family Controls and shared App Group present, debug entitlement absent; app NFC present; deferred AI capabilities absent. Release receipt: `release/builds/2.4-6.json`.

App Store Connect query confirmed no 2.4 (5) build after the canceled attempt. Apple accepted the corrected package without errors. Processing is VALID; internal state is IN_BETA_TESTING; membership in Amit Internal is verified. Build/delivery ID: `ad212863-6283-479b-af04-8a91ccd435b6`. Testing notes and export compliance are saved; external review was not submitted. Screenshots and captions are preserved on the [Notion reliability task](https://app.notion.com/p/41016e0e0e3a818e843ec19a9777c384); temporary-session screenshot is an explicit empty-token/presentation fixture, and manual validation uses real missing authorization. Both were visually inspected.

### 2.4 (6) audit status

All six confirmed issue groups are fixed with regressions in the source above. The audit contains 15 state-machine areas. New suites pass 29 checks (13 lifecycle, 8 mutation, 4 NFC, 4 migration), plus the real interprocess lease test. Existing suites and modern-runtime UI checks pass as detailed above. The workspace dashboard records the same outcome. Physical-device acceptance and the listed platform risks remain open; they are not labeled fixed by automated evidence.

The complete audit remains this repository file. A proposed full-file attachment to Notion was blocked by automatic approval review because that upload was not explicitly authorized; only the separately authorized results and screenshots are published there. No workaround upload was attempted.

### 2.4 (7) recovery follow-up release

SM-07 adds the actionable warning/recovery flow described above. Production source: `068d1904e719d3daca4d50ef91c719f232e85ca0`. IPA SHA-256: `7305f7aa9de55521826127f19ab09a1819c6e44db0a643964c41a69d845d851b`. Distribution signatures and profiles verified for app and extension; Family Controls/App Group present, debug entitlement absent; NFC present for app. Deferred AI remains excluded. Receipt: `release/builds/2.4-7.json`.

Verification: 5 production retry contracts + 8 production presentation checks; 5/5 native UI flows on iOS 26.5; extended list → retry → permission flow 1/1 on iOS 27 after fixing the pre-release sheet conflict. Recovery instructions and final permission screen were visually inspected and screenshot evidence saved in the existing Notion QA task. Physical enforcement and iOS 17.5 remain unverified. Apple upload succeeded without errors. Processing is VALID; internal state IN_BETA_TESTING; Amit Internal membership verified. Build/delivery ID: `f5039c6d-ec9a-4817-8130-ef1f704becf8`. Test notes and export compliance are saved; no external review submitted. Build 2.4 (7) is the latest internal release.
