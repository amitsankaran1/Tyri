import Foundation
struct DeviceActivityName: Hashable { let rawValue: String }
struct DeviceActivityEvent {
 struct Name: Equatable { let rawValue: String; init(rawValue: String) { self.rawValue = rawValue }; init(_ value: String) { rawValue = value } }
 let applications: Set<Int>; let categories: Set<Int>; let webDomains: Set<Int>; let threshold: DateComponents
 let includesPastActivity: Bool
 init(applications: Set<Int>, categories: Set<Int>, webDomains: Set<Int>, threshold: DateComponents, includesPastActivity: Bool = false) { self.includesPastActivity = includesPastActivity; self.applications = applications; self.categories = categories; self.webDomains = webDomains; self.threshold = threshold }
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
 static var events: [DeviceActivityName: [DeviceActivityEvent.Name: DeviceActivityEvent]] = [:]
 static var schedules: [DeviceActivityName: DeviceActivitySchedule] = [:]
 static var maxActivities = 20
 static var maxEvents = 1000
 static var fail = false
 static var starts = 0
 var activities: [DeviceActivityName] { Array(Self.schedules.keys) }
 func startMonitoring(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule, events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) throws {
  if Self.fail || events.count > Self.maxEvents || (Self.schedules[name] == nil && Self.schedules.count >= Self.maxActivities) { throw NSError(domain: "QA", code: 1) }
  Self.starts += 1; Self.schedules[name] = schedule; Self.events[name] = events
 }
 func stopMonitoring(_ names: [DeviceActivityName]) { for n in names { Self.schedules[n] = nil } }
}
extension DeviceActivityEvent.Name: Hashable {}
enum SharedDefaults {
 static let suite = UserDefaults(suiteName: "tyri-callback-tests-\(UUID())")!
 enum Keys {
  static let adHocSession = "adhoc"
  static func usageGeneration(blockID: UUID) -> String { "generation.\(blockID)" }
  static func usageError(blockID: UUID) -> String { "error.\(blockID)" }
  static func usageLockError(blockID: UUID) -> String { "lockerror.\(blockID)" }
  static func usageLockEnd(blockID: UUID) -> String { "lock.\(blockID)" }
  static func breakEnd(blockID: UUID) -> String { "break.\(blockID)" }
  static func breakUsed(blockID: UUID) -> String { "used.\(blockID)" }
  static func running(blockID: UUID) -> String { "running.\(blockID)" }
 }
}
enum Kind { case timer, schedule, tag }
struct BlockRule { var id: UUID = UUID(); var name: String = ""; var appGroupIDs: [UUID] = []; var type: Kind = .timer; var isEnabled = false; var usageLockMinutes = 180; var usageLimitMinutes: Int? = 30 }
struct AppGroup: Codable, Equatable { var id = UUID(); var name = "Test list" }
enum BlockResolution {
 struct Tokens { var apps: Set<Int> = [1]; var categories: Set<Int> = []; var webDomains: Set<Int> = []; var domains: Set<String> = ["example.com"]; var isEmpty: Bool { false } }
 static var blocks: [UUID: BlockRule] = [:]
 static func loadBlock(id: UUID) -> BlockRule? { blocks[id] }
 static func loadGroups() -> [AppGroup] { [] }
 static func tokens(for block: BlockRule, groups: [AppGroup]) -> Tokens { Tokens() }
}
enum State { static var shield = false; static var shields: Set<UUID> = [] }
enum BlockingActuator {
 static func start(blockID: UUID, bypassWeekday: Bool, setRunningFlag: Bool, resetBreakAllowance: Bool = true) { State.shield = true; State.shields.insert(blockID) }
 static func apply(tokens: BlockResolution.Tokens, blockID: UUID) { State.shield = true; State.shields.insert(blockID) }
 static func end(blockID: UUID) { State.shield = false; State.shields.remove(blockID) }
 static func clearShields(blockID: UUID) { State.shield = false; State.shields.remove(blockID) }
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
  var checks = 0;var failures = 0
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
  // A completed allowance must use a genuinely new monitor identity.
  BlockResolution.blocks[id]!.type = .timer
  UsageMonitoring.startUsageMonitor(forBlockID: id)
  let firstCycle = UsageMonitoring.usageActivityName(for: id)
  monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: firstCycle)
  check(State.shield, "first cycle threshold shields")
  SharedDefaults.suite.set(Date().addingTimeInterval(-1), forKey: key)
  monitor.intervalDidEnd(for: lock)
  let secondCycle = UsageMonitoring.usageActivityName(for: id)
  check(firstCycle != secondCycle && !DeviceActivityCenter().activities.contains(firstCycle), "expiry rotates and removes consumed allowance")
  monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: firstCycle)
  check(SharedDefaults.suite.object(forKey: key) == nil, "stale first-cycle threshold cannot consume new allowance")
  monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: secondCycle)
  check(State.shield && SharedDefaults.suite.object(forKey: key) != nil, "second allowance triggers second lockout")
  check(DeviceActivityCenter.events[secondCycle]?[UsageMonitoring.usageEventName]?.includesPastActivity == false, "fresh allowance excludes past activity")
  let secondEnd = SharedDefaults.suite.object(forKey: key) as! Date
  monitor.intervalDidEnd(for: lock)
  check(State.shield && SharedDefaults.suite.object(forKey: key) as? Date == secondEnd, "second lockout cannot end early")
  DeviceActivityCenter.fail = true
  check(!UsageMonitoring.startUsageMonitor(forBlockID: id), "failed rearm is reported")
  check(UsageMonitoring.usageActivityName(for: id) == secondCycle && SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageError(blockID: id)) != nil, "failed replacement preserves current registration and records error")
  DeviceActivityCenter.fail = false
  UsageMonitoring.startUsageMonitor(forBlockID: id)
  check(SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageError(blockID: id)) == nil, "retry clears tracking error")
  UsageMonitoring.stopLockout(for: id)
  DeviceActivityCenter.fail = true
  UsageMonitoring.startLockout(blockID: id, minutes: 1)
  let savedEnd = SharedDefaults.suite.object(forKey: key) as! Date
  check(State.shield && SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageLockError(blockID: id)) != nil, "failed lock registration retains shield and deadline with error")
  DeviceActivityCenter.fail = false
  UsageMonitoring.reconcileLockout(blockID: id)
  check(SharedDefaults.suite.object(forKey: key) as? Date == savedEnd && SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageLockError(blockID: id)) == nil, "repair restores expiry monitor without extending lock")
  check(DeviceActivityCenter.schedules[lock]?.warningTime?.second != nil, "short recovered lock gets deadline warning")
  let now = Date()
  do {
   DeviceActivityCenter.fail = true
   do { try AdHocMonitoring.start(group: AppGroup(), minutes: 30, now: now); preconditionFailure("registration should fail") } catch {}
   check(AdHocMonitoring.session == nil, "ad hoc registration failure rolls back session")
   DeviceActivityCenter.fail = false
   try AdHocMonitoring.start(group: AppGroup(), minutes: 30, now: now)
   let session = AdHocMonitoring.session!
   let independentID = UUID()
   BlockingActuator.apply(tokens: BlockResolution.Tokens(), blockID: independentID)
   check(session.endsAt.timeIntervalSince(session.startedAt) == 1800, "ad hoc duration persists exactly")
   AdHocMonitoring.reconcile(now: now.addingTimeInterval(60))
   check(AdHocMonitoring.session?.id == session.id && State.shield, "early callback preserves ad hoc session")
   try AdHocMonitoring.requestRelease(now: now)
   AdHocMonitoring.release(now: now.addingTimeInterval(299))
   check(AdHocMonitoring.session != nil, "early release requires full wait")
   AdHocMonitoring.release(now: now.addingTimeInterval(301))
   check(AdHocMonitoring.session == nil, "explicit release after wait ends session")
   check(State.shields.contains(independentID) && !State.shields.contains(session.id), "ad hoc release preserves independent shield")
   try AdHocMonitoring.start(group: AppGroup(), minutes: 60, now: now)
   let newer = AdHocMonitoring.session!
   AdHocMonitoring.finish(id: session.id)
   check(AdHocMonitoring.session?.id == newer.id, "stale release cannot end later session")
   AdHocMonitoring.reconcile(now: now.addingTimeInterval(3601))
   check(AdHocMonitoring.session == nil && !State.shield, "background expiry clears temporary session")
  } catch { preconditionFailure("Unexpected ad hoc error: \(error)") }
  // Saturate the real documented activity budget, then consume an allowance.
  DeviceActivityCenter.schedules = [:];DeviceActivityCenter.events = [:]
  let cappedID = UUID();BlockResolution.blocks[cappedID] = BlockRule(id: cappedID)
  UsageMonitoring.startUsageMonitor(forBlockID: cappedID)
  for i in 0..<19 { try! DeviceActivityCenter().startMonitoring(DeviceActivityName(rawValue: "other.\(i)"), during: UsageMonitoring.allDaySchedule) }
  monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: UsageMonitoring.usageActivityName(for: cappedID))
  let capacityOK = SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageLockError(blockID: cappedID)) == nil
  print("\(capacityOK ? "PASS" : "FAIL"): consumed allowance releases a slot for lockout at 20-activity capacity")
  if capacityOK { checks += 1 } else { failures += 1 }
  DeviceActivityCenter.schedules = [:];DeviceActivityCenter.events = [:]
  for minutes in stride(from: 5, through: 1435, by: 5) {
   let id = UUID();BlockResolution.blocks[id] = BlockRule(id: id)
   UsageMonitoring.startLockout(blockID: id, minutes: minutes)
   let end = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as! Date
   check(abs(end.timeIntervalSinceNow - Double(minutes * 60)) < 2, "exact lock deadline \(minutes)")
   let schedule = DeviceActivityCenter.schedules[UsageMonitoring.lockActivityName(for: id)]!
   let start = Calendar.current.date(from: schedule.intervalStart)!, finish = Calendar.current.date(from: schedule.intervalEnd)!
   check(finish.timeIntervalSince(start) >= 900, "OS interval minimum \(minutes)")
   check(abs(finish.addingTimeInterval(-Double(schedule.warningTime?.second ?? 0)).timeIntervalSince(end)) < 1, "warning at real deadline \(minutes)")
   UsageMonitoring.stopLockout(for: id)
  }
  DeviceActivityCenter.maxEvents = 1
  let fallbackID=UUID();BlockResolution.blocks[fallbackID] = BlockRule(id:fallbackID)
  check(UsageMonitoring.startUsageMonitor(forBlockID:fallbackID), "progress event rejection preserves enforcement-only registration")
  DeviceActivityCenter.maxEvents = 1000
  print("RESULT: \(checks) passed / \(failures) failed lifecycle regression checks (production callbacks, usage and break helpers; OS/store doubles)")
 }
}
