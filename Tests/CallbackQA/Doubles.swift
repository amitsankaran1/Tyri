import Foundation
struct DeviceActivityName: Hashable { let rawValue: String }
struct DeviceActivityEvent {
 struct Name: Equatable { let rawValue: String }
 init(applications: Set<Int>, categories: Set<Int>, webDomains: Set<Int>, threshold: DateComponents) {}
}
struct DeviceActivitySchedule {
 let intervalStart: DateComponents; let intervalEnd: DateComponents; let repeats: Bool; var warningTime: DateComponents? = nil
}
class DeviceActivityMonitor {
 func intervalDidStart(for activity: DeviceActivityName) {}
 func intervalDidEnd(for activity: DeviceActivityName) {}
 func intervalWillEndWarning(for activity: DeviceActivityName) {}
 func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {}
}
struct DeviceActivityCenter {
 static var schedules: [DeviceActivityName: DeviceActivitySchedule] = [:]
 static var fail = false
 static var starts = 0
 var activities: [DeviceActivityName] { Array(Self.schedules.keys) }
 func startMonitoring(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule, events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) throws {
  if Self.fail { throw NSError(domain: "QA", code: 1) }
  Self.starts += 1; Self.schedules[name] = schedule
 }
 func stopMonitoring(_ names: [DeviceActivityName]) { for n in names { Self.schedules[n] = nil } }
}
extension DeviceActivityEvent.Name: Hashable {}
enum SharedDefaults {
 static let suite = UserDefaults(suiteName: "tyri-callback-tests-\(UUID())")!
 enum Keys {
  static func usageLockEnd(blockID: UUID) -> String { "lock.\(blockID)" }
  static func breakEnd(blockID: UUID) -> String { "break.\(blockID)" }
  static func breakUsed(blockID: UUID) -> String { "used.\(blockID)" }
  static func running(blockID: UUID) -> String { "running.\(blockID)" }
 }
}
enum Kind { case timer, schedule, tag }
struct BlockRule { var id: UUID; var type: Kind = .timer; var isEnabled = false; var usageLockMinutes = 180; var usageLimitMinutes: Int? = 30 }
struct AppGroup {}
enum BlockResolution {
 struct Tokens { var apps: Set<Int> = [1]; var categories: Set<Int> = []; var webDomains: Set<Int> = []; var isEmpty: Bool { false } }
 static var blocks: [UUID: BlockRule] = [:]
 static func loadBlock(id: UUID) -> BlockRule? { blocks[id] }
 static func loadGroups() -> [AppGroup] { [] }
 static func tokens(for block: BlockRule, groups: [AppGroup]) -> Tokens { Tokens() }
}
enum State { static var shield = false }
enum BlockingActuator {
 static func start(blockID: UUID, bypassWeekday: Bool, setRunningFlag: Bool, resetBreakAllowance: Bool = true) { State.shield = true }
 static func apply(tokens: BlockResolution.Tokens, blockID: UUID) { State.shield = true }
 static func end(blockID: UUID) { State.shield = false }
 static func clearShields(blockID: UUID) { State.shield = false }
}
enum ScheduleEnforcement {
 static func reconcile(blockID: UUID) {}
 static func reconcile(block: BlockRule) {}
}
@main struct CallbackQA {
 static func main() {
  let id = UUID(); BlockResolution.blocks[id] = BlockRule(id: id)
  let monitor = TyriMonitorExtension()
  let lock = DeviceActivityName(rawValue: "lock.\(id)")
  let usage = DeviceActivityName(rawValue: "usage.\(id)")
  let key = SharedDefaults.Keys.usageLockEnd(blockID: id)
  let end = Date().addingTimeInterval(10800)
  var checks = 0
  func check(_ condition: Bool, _ label: String) { precondition(condition, label); checks += 1 }
  SharedDefaults.suite.set(end, forKey: key); State.shield = true
  monitor.intervalDidEnd(for: lock)
  check(State.shield && SharedDefaults.suite.object(forKey: key) as? Date == end, "early end preserves deadline and shield")
  State.shield = false; UsageMonitoring.reconcileLockout(blockID: id)
  check(State.shield, "foreground restores live usage shield")
  let starts = DeviceActivityCenter.starts
  monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: usage)
  check(DeviceActivityCenter.starts == starts && SharedDefaults.suite.object(forKey: key) as? Date == end, "duplicate threshold preserves monitor and deadline")
  UsageMonitoring.stopLockout(for: id); State.shield = false
  monitor.intervalDidStart(for: lock); monitor.intervalDidEnd(for: lock)
  check(!State.shield && SharedDefaults.suite.object(forKey: key) == nil, "stale callbacks do not create an orphan shield")
  SharedDefaults.suite.set(Date().addingTimeInterval(-1), forKey: key); State.shield = true
  monitor.intervalDidEnd(for: lock)
  check(!State.shield && SharedDefaults.suite.object(forKey: key) == nil, "genuine expiry releases")
  let afterExpiry = DeviceActivityCenter.starts; monitor.intervalDidEnd(for: lock)
  check(DeviceActivityCenter.starts == afterExpiry, "duplicate expiry does not reset budget again")
  BlockResolution.blocks[id]!.isEnabled = true
  SharedDefaults.suite.set(Date().addingTimeInterval(-1), forKey: key)
  monitor.intervalDidEnd(for: lock)
  check(State.shield, "expiry preserves manual block")
  BlockResolution.blocks[id]!.type = .tag; State.shield = false
  monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: usage)
  check(!State.shield, "old threshold ignores changed rule type")
  State.shield = true; DeviceActivityCenter.fail = true
  BreakMonitoring.startBreak(blockID: id, minutes: 5)
  check(State.shield && BreakMonitoring.breakEnd(blockID: id) == nil, "failed break registration keeps shield")
  DeviceActivityCenter.fail = false
  BreakMonitoring.startBreak(blockID: id, minutes: 5)
  let activity = BreakMonitoring.breakActivityName(for: id)
  let schedule = DeviceActivityCenter.schedules[activity]!
  check(schedule.warningTime?.minute == 10, "five minute break uses ten minute warning on fifteen minute window")
  let breakEnd = BreakMonitoring.breakEnd(blockID: id)!
  monitor.intervalDidEnd(for: activity)
  check(BreakMonitoring.breakEnd(blockID: id) == breakEnd && !State.shield, "early break end preserves current break")
  SharedDefaults.suite.set(Date().addingTimeInterval(-1), forKey: SharedDefaults.Keys.breakEnd(blockID: id))
  monitor.intervalWillEndWarning(for: activity)
  check(State.shield && BreakMonitoring.breakEnd(blockID: id) == nil, "warning restores shield at real break expiry")
  print("PASS: \(checks) lifecycle regression checks (production callbacks, usage and break helpers; OS/store doubles)")
 }
}
