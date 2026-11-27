// TSK-174 vacation mode. Production enforcement code; OS doubles; UTC calendar.
import Foundation
var passed = 0, failed = 0
func expect(_ ok: Bool, _ label: String) { print("\(ok ? "PASS" : "FAIL"): \(label)"); if ok { passed += 1 } else { failed += 1 } }
let suite = SharedDefaults.suite
let ext = TyriMonitorExtension()
func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
func shielded(_ id: UUID) -> Bool { ManagedSettingsStore.saved[BlockingActuator.appsStoreName(for: id)]?.shield.applications?.isEmpty == false }
func lockEnd(_ id: UUID) -> Date? { suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date }

var selection = FamilyActivitySelection(); selection.applicationTokens = [11, 12]
let list = AppGroup(name: "Social", selection: selection)
let workday = BlockingSchedule(startHour: 9, startMinute: 0, endHour: 17, endMinute: 0, weekdays: Set(1...7))
var paused = BlockRule(name: "Work", type: .schedule, appGroupIDs: [list.id], schedule: workday)
let kept = BlockRule(name: "Kept", type: .schedule, appGroupIDs: [list.id], schedule: workday)
let timer = BlockRule(name: "Limit", type: .timer, appGroupIDs: [list.id], usageLimitMinutes: 10, usageLockMinutes: 30)
func save() { suite.set(try! JSONEncoder().encode([paused, kept, timer]), forKey: SharedDefaults.Keys.blocks) }
save()
suite.set(try! JSONEncoder().encode([list]), forKey: SharedDefaults.Keys.groups)
func windowStart(_ block: BlockRule) { ext.intervalDidStart(for: DeviceActivityName(rawValue: "block.\(block.id.uuidString)")) }
func vacationCallback(_ plan: VacationPlan) {
    ext.intervalDidEnd(for: DeviceActivityName(rawValue: VacationMode.namespace(plan) + ".r-native"))
}

// Start before the workday; resume two days later at noon, mid-window.
QAClock.now = at("2026-12-01T08:00:00Z")
expect(VacationMode.start(blockIDs: [], resumeAt: at("2026-12-03T12:00:00Z")) == nil, "empty selection is rejected")
expect(VacationMode.start(blockIDs: [paused.id], resumeAt: at("2026-12-01T07:00:00Z")) == nil, "a past resume time is rejected")
let newYork = TimeZone(identifier: "America/New_York")!
let plan = VacationMode.start(blockIDs: [paused.id, timer.id], resumeAt: at("2026-12-03T12:00:30Z"), timeZone: newYork)!
expect(plan.resumeAt == at("2026-12-03T12:00:00Z") && plan.timeZoneID == "America/New_York",
       "resume is one absolute instant (minute precision) recorded with the zone it was chosen in")

// Automatic schedule activation is suppressed only for selected blocks.
QAClock.now = at("2026-12-01T09:00:00Z")
windowStart(paused); windowStart(kept)
expect(!shielded(paused.id), "selected schedule window that starts during vacation stays off")
expect(shielded(kept.id), "unselected block keeps enforcing on its schedule")

// Usage limit reached during vacation: no lockout, fresh allowance at resume.
UsageMonitoring.startUsageMonitor(forBlockID: timer.id)
let firstAllowance = UsageMonitoring.usageActivityName(for: timer.id)
QAClock.now = at("2026-12-01T10:00:00Z")
ext.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: firstAllowance)
expect(lockEnd(timer.id) == nil && !shielded(timer.id), "usage limit reached during vacation does not lock")
expect(suite.bool(forKey: VacationMode.suppressedLimitKey(timer.id)), "the suppressed limit is remembered for resume")

// Explicit Block now still wins.
paused.isEnabled = true; save()
ScheduleEnforcement.reconcile(blockID: paused.id)
expect(shielded(paused.id), "Block now enforces a paused block")
paused.isEnabled = false; save()
ScheduleEnforcement.reconcile(blockID: paused.id)
expect(!shielded(paused.id), "turning Block now off returns to the vacation pause")

// A stale callback from an earlier monitor before the resume time is a no-op.
QAClock.now = at("2026-12-02T09:30:00Z")
ext.intervalDidStart(for: DeviceActivityName(rawValue: VacationMode.namespace(plan) + ".r-native"))
expect(VacationMode.plan != nil && !shielded(paused.id), "an early vacation callback does not end the pause")

// Resume at noon on day 3: mid-window re-shield, fresh allowance.
QAClock.now = at("2026-12-03T12:00:00Z")
vacationCallback(plan)
expect(VacationMode.plan == nil, "resume callback clears the vacation")
expect(shielded(paused.id), "a window in progress at the resume time re-shields without opening Tyri")
let freshAllowance = UsageMonitoring.usageActivityName(for: timer.id)
expect(freshAllowance != firstAllowance && DeviceActivityCenter.schedules[freshAllowance] != nil,
       "suppressed usage limit gets a fresh allowance at resume")
expect(!suite.bool(forKey: VacationMode.suppressedLimitKey(timer.id)) && lockEnd(timer.id) == nil,
       "resume does not lock immediately for usage from the vacation")
ext.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: freshAllowance)
expect(lockEnd(timer.id) != nil && shielded(timer.id), "after resume the usage limit locks normally")

// An activation already under way is never lifted.
UsageMonitoring.stopLockout(for: timer.id)
BlockingActuator.clearShields(blockID: timer.id)
QAClock.now = at("2026-12-04T10:00:00Z")
UsageMonitoring.startUsageMonitor(forBlockID: timer.id)
ext.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: UsageMonitoring.usageActivityName(for: timer.id))
let existingLock = lockEnd(timer.id)
windowStart(paused)
expect(shielded(paused.id) && existingLock != nil, "control: window and usage lock active before vacation")
let second = VacationMode.start(blockIDs: [paused.id, timer.id], resumeAt: at("2026-12-08T06:00:00Z"))!
ScheduleEnforcement.reconcile(blockID: paused.id)
UsageMonitoring.reconcileLockout(blockID: timer.id)
expect(shielded(paused.id), "a window that began before vacation runs to its end")
expect(lockEnd(timer.id) == existingLock && shielded(timer.id), "an existing usage lockout keeps its deadline")
QAClock.now = at("2026-12-04T17:00:00Z")
ext.intervalDidEnd(for: DeviceActivityName(rawValue: "block.\(paused.id.uuidString)"))
expect(!shielded(paused.id), "the existing window still ends normally")
QAClock.now = at("2026-12-05T09:00:00Z")
windowStart(paused)
expect(!shielded(paused.id), "the next window is paused")

// Changing the plan keeps the original pause start; dropping a block resumes it now.
QAClock.now = at("2026-12-05T10:00:00Z")
let changed = VacationMode.start(blockIDs: [paused.id, timer.id], resumeAt: at("2026-12-09T06:00:00Z"))!
ScheduleEnforcement.reconcile(blockID: paused.id)
expect(changed.id != second.id && !shielded(paused.id), "extending the vacation cannot revive a suppressed window")
_ = VacationMode.start(blockIDs: [timer.id], resumeAt: at("2026-12-09T06:00:00Z"))
expect(shielded(paused.id), "removing a block from the vacation restores its current window immediately")
VacationMode.start(blockIDs: [paused.id, timer.id], resumeAt: at("2026-12-09T06:00:00Z"))
ScheduleEnforcement.reconcile(blockID: paused.id)
expect(shielded(paused.id), "re-adding a block during its window doesn't lift that window")

// Ending early restores immediately.
QAClock.now = at("2026-12-06T09:30:00Z")
windowStart(paused)
expect(!shielded(paused.id), "control: paused again on the next window")
VacationMode.end()
expect(VacationMode.plan == nil && shielded(paused.id), "ending early re-shields the current window right away")

// The pause expires by time even when its own callback never arrives.
QAClock.now = at("2026-12-07T08:00:00Z")
VacationMode.start(blockIDs: [paused.id], resumeAt: at("2026-12-07T12:00:00Z"))
QAClock.now = at("2026-12-07T09:00:00Z")
windowStart(paused)
expect(!shielded(paused.id), "control: paused window")
QAClock.now = at("2026-12-08T09:00:00Z")
windowStart(paused)
expect(shielded(paused.id), "after the resume time the next window enforces without the vacation callback")
expect(VacationMode.reconcile() && VacationMode.plan == nil, "foreground reconcile clears the expired plan")

print("RESULT: \(passed)/\(passed + failed) vacation checks passed; production code with OS doubles, not device enforcement")
if failed > 0 { exit(1) }
