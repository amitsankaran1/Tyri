// Regression R1: production extension + shared enforcement code reading an
// unreadable (forward-incompatible / corrupt) App Group store.
import Foundation
var passed = 0, failed = 0
func expect(_ ok: Bool, _ label: String) { print("\(ok ? "PASS" : "FAIL"): \(label)"); if ok { passed += 1 } else { failed += 1 } }
func observe(_ ok: Bool, _ label: String) { print("\(ok ? "OBSERVED" : "not observed"): \(label)") }
let suite = SharedDefaults.suite
func apps(_ id: UUID) -> Set<Int>? { ManagedSettingsStore.saved[BlockingActuator.appsStoreName(for: id)]?.shield.applications }
var selection = FamilyActivitySelection(); selection.applicationTokens = [11, 12]
let list = AppGroup(name: "Social", selection: selection)
let schedule = BlockRule(name: "Always", type: .schedule, appGroupIDs: [list.id],
                         schedule: BlockingSchedule(startHour: 0, startMinute: 0, endHour: 0, endMinute: 0, weekdays: Set(1...7)))
let timer = BlockRule(name: "Instagram 10", type: .timer, appGroupIDs: [list.id], usageLimitMinutes: 10, usageLockMinutes: 30)
let goodBlocks = try! JSONEncoder().encode([schedule, timer])
let goodGroups = try! JSONEncoder().encode([list])
// A future build adds a rule type; this build cannot decode it (TestFlight downgrade / corruption).
let unreadable = Data("[{\"id\":\"\(UUID())\",\"name\":\"Future\",\"type\":\"location\"}]".utf8)
suite.set(goodBlocks, forKey: SharedDefaults.Keys.blocks); suite.set(goodGroups, forKey: SharedDefaults.Keys.groups)
let ext = TyriMonitorExtension()

// Control: readable data.
ext.intervalDidStart(for: DeviceActivityName(rawValue: "block.\(schedule.id.uuidString)"))
expect(apps(schedule.id) == [11, 12], "control: schedule start shields the list with readable data")

// R1a: unreadable LISTS + schedule callback.
suite.set(Data("not-json".utf8), forKey: SharedDefaults.Keys.groups)
ext.intervalDidStart(for: DeviceActivityName(rawValue: "block.\(schedule.id.uuidString)"))
expect(apps(schedule.id) == [11, 12], "R1a unreadable lists: in-window schedule callback preserves the active shield (apps=\(String(describing: apps(schedule.id))))")
print("   shieldError: \(suite.string(forKey: SharedDefaults.Keys.shieldError(blockID: schedule.id)) ?? "nil")")
suite.set(goodGroups, forKey: SharedDefaults.Keys.groups)

// R1b: usage lock active, unreadable lists, duplicate/early lock callback before deadline.
QAClock.now = Date()
UsageMonitoring.startLockout(blockID: timer.id, minutes: 30)
let end = suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) as! Date
let expirySchedule = DeviceActivityCenter.schedules[UsageMonitoring.lockActivityName(for: timer.id)]!
expect(expirySchedule.intervalEnd.calendar?.identifier == .gregorian && expirySchedule.intervalEnd.timeZone?.secondsFromGMT() == 0, "absolute deadline includes an explicit Gregorian UTC calendar")
expect(expirySchedule.intervalEnd.calendar?.date(from: expirySchedule.intervalEnd) == end, "native absolute components represent the persisted deadline")
expect(apps(timer.id) == [11, 12], "control: usage threshold lockout shields")
suite.set(Data("not-json".utf8), forKey: SharedDefaults.Keys.groups)
QAClock.now = end.addingTimeInterval(-25 * 60) // 5 minutes into a 30-minute lock
ext.intervalDidStart(for: UsageMonitoring.lockActivityName(for: timer.id))
expect(apps(timer.id) == [11, 12], "R1b unreadable lists: early lock callback preserves the usage-lock shield (apps=\(String(describing: apps(timer.id))))")
observe((suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) as? Date) == end, "   ...while the persisted deadline still says locked until \(end)")
suite.set(goodGroups, forKey: SharedDefaults.Keys.groups)
UsageMonitoring.reconcileLockout(blockID: timer.id, now: QAClock.now) // restore for next case
expect(apps(timer.id) == [11, 12], "control: reconcile with readable lists restores lock shield")

// R1c: unreadable RULES at the real lock deadline.
suite.set(unreadable, forKey: SharedDefaults.Keys.blocks)
QAClock.now = end.addingTimeInterval(60)
ext.intervalWillEndWarning(for: UsageMonitoring.lockActivityName(for: timer.id))
ext.intervalDidEnd(for: UsageMonitoring.lockActivityName(for: timer.id))
expect(apps(timer.id) == nil && suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) == nil,
        "R1c unreadable rules: expired lock releases shield and deadline even with unreadable rules")
suite.set(goodBlocks, forKey: SharedDefaults.Keys.blocks)
ext.intervalDidEnd(for: UsageMonitoring.lockActivityName(for: timer.id))
expect(suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) == nil, "control: same callback with readable rules releases the expired lock")
// Forward-incompatible nested picker data must fail the entire list decode.
var encodedGroup = try! JSONSerialization.jsonObject(with: goodGroups) as! [[String: Any]]
encodedGroup[0]["selectionData"] = Data("unreadable-selection".utf8).base64EncodedString()
suite.set(try! JSONSerialization.data(withJSONObject: encodedGroup), forKey: SharedDefaults.Keys.groups)
expect(BlockResolution.loadGroups() == nil, "undecodable picker selection is not silently replaced with empty tokens")
suite.set(goodGroups, forKey: SharedDefaults.Keys.groups)

// The original review fixture is syntactically a valid list with a dangling ID,
// rather than a decode failure. Both must preserve existing protection.
suite.set(unreadable, forKey: SharedDefaults.Keys.groups)
ext.intervalDidStart(for: DeviceActivityName(rawValue: "block.\(schedule.id.uuidString)"))
expect(apps(schedule.id) == [11, 12], "missing referenced list preserves the active schedule shield")
suite.set(goodGroups, forKey: SharedDefaults.Keys.groups)

var manual = timer; manual.isEnabled = true
suite.set(try! JSONEncoder().encode([manual]), forKey: SharedDefaults.Keys.blocks)
UsageMonitoring.startLockout(blockID: timer.id, minutes: 5)
let manualEnd = suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) as! Date
suite.set(unreadable, forKey: SharedDefaults.Keys.blocks)
QAClock.now = manualEnd.addingTimeInterval(1)
UsageMonitoring.reconcileLockout(blockID: timer.id)
expect(apps(timer.id) == [11, 12], "unreadable rule expiry preserves independently active manual protection")
expect(suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) == nil, "manual protection does not strand an expired timed deadline")
// Old builds had no manual-owner snapshot: unknown must not mean disabled.
suite.set(try! JSONEncoder().encode([manual]), forKey: SharedDefaults.Keys.blocks)
UsageMonitoring.startLockout(blockID: timer.id, minutes: 5)
let legacyEnd = suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) as! Date
suite.removeObject(forKey: "usageLockManual.\(timer.id)")
suite.set(unreadable, forKey: SharedDefaults.Keys.blocks)
QAClock.now = legacyEnd.addingTimeInterval(1)
UsageMonitoring.reconcileLockout(blockID: timer.id)
expect(apps(timer.id) == [11, 12], "legacy unknown manual ownership preserves independent protection")
expect(suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: timer.id)) == nil, "legacy timed ownership still expires")
let calendar = Calendar.current
let today = calendar.startOfDay(for: QAClock.now)
QAClock.now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
let bounded = BlockRule(name: "Morning", type: .schedule, appGroupIDs: [list.id], schedule: BlockingSchedule(startHour: 9, endHour: 11, weekdays: Set(1...7)))
suite.set(try! JSONEncoder().encode([bounded]), forKey: SharedDefaults.Keys.blocks)
ScheduleEnforcement.reconcile(block: bounded, now: QAClock.now)
expect(apps(bounded.id) == [11, 12], "bounded schedule starts with readable data")
suite.set(Data("not-json".utf8), forKey: SharedDefaults.Keys.groups)
QAClock.now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
ScheduleEnforcement.reconcile(block: bounded, now: QAClock.now)
expect(apps(bounded.id) == nil, "known schedule expiry releases even if target lists are unreadable")
print("RESULT R1: \(passed) controls passed, \(failed) controls failed")
suite.removePersistentDomain(forName: SharedDefaults.qaName)
exit(failed == 0 ? 0 : 1)
