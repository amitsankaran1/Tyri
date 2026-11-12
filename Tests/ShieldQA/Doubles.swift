import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum NativeProbe {
 static var onWrite: (() -> Void)?
 static var writes = 0
 static var lockedCalls = 0
 static func write() {
  writes += 1
  let path = ProcessInfo.processInfo.environment["TYRI_TRANSACTION_PATH"] ?? NSTemporaryDirectory() + "tyri-enforcement-tests-\(ProcessInfo.processInfo.processIdentifier).lock"
  let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
  precondition(fd >= 0)
  if flock(fd, LOCK_EX | LOCK_NB) != 0 { lockedCalls += 1 }
  else { flock(fd, LOCK_UN) }
  close(fd)
  if let hook = onWrite { onWrite = nil; hook() }
 }
}
typealias ApplicationToken = Int
typealias WebDomainToken = Int
typealias ActivityCategoryToken = Int
enum WebContentSettings { typealias FilterPolicy = ManagedSettingsStore.Filter }
struct WebDomain: Hashable { let domain: String }
class ManagedSettingsStore {
 struct Name: Hashable { let rawValue: String }
 enum Policy: Equatable { case specific(Set<Int>, except: Set<Int> = []); case all }
 enum Filter: Equatable { case specific(Set<WebDomain>) }
 class Shield {
  var applications: Set<Int>? { didSet { NativeProbe.write(); if let v=applications, v.count > 50 || ManagedSettingsStore.dropApps { applications=nil } } }
  var applicationCategories: Policy? { didSet { NativeProbe.write() } }
  var webDomains: Set<Int>? { didSet { NativeProbe.write(); if let v=webDomains, v.count > 50 { webDomains=nil } } }
 }
 class WebContent { var blockedByFilter: Filter? { didSet { NativeProbe.write(); if ManagedSettingsStore.dropDomains { blockedByFilter=nil } } } }
 static var dropApps=false, dropDomains=false
 static var saved: [Name: ManagedSettingsStore] = [:]
 var shield=Shield();var webContent=WebContent()
 init() {}
 convenience init(named name: Name) { self.init();if let old=Self.saved[name] { shield=old.shield;webContent=old.webContent } else {Self.saved[name]=self} }
 func clearAllSettings() { shield.applications=nil;shield.webDomains=nil;shield.applicationCategories=nil;webContent.blockedByFilter=nil }
}
enum SharedDefaults {
 static let name=ProcessInfo.processInfo.environment["TYRI_SHIELD_SUITE"] ?? "tyri-shield-tests-\(UUID())"
 static let suite=UserDefaults(suiteName:name)!
 enum Keys {
  static func running(blockID:UUID)->String {"running.\(blockID)"}
  static func shieldChunkCount(blockID:UUID)->String {"chunks.\(blockID)"}
  static func shieldAudit(blockID:UUID)->String {"audit.\(blockID)"}
  static func shieldError(blockID:UUID)->String {"shieldError.\(blockID)"}
 }
}
struct QAGroup { var id = UUID() }
struct BlockRule {var appGroupIDs: Set<UUID> = []; enum Kind {case schedule,timer};let id:UUID;var type:Kind = .timer;var schedule:Schedule?=nil }
struct Schedule {var weekdays:Set<Int>=[]}
enum BlockResolution {
 static var known: Set<UUID> = []
 static func loadBlocks() -> [BlockRule]? { known.subtracting(missing).map { BlockRule(id: $0) } }
 struct Tokens: Codable, Equatable {var apps:Set<Int>=[];var categories:Set<Int>=[];var webDomains:Set<Int>=[];var domains:Set<String>=[]}
 static var selection=Tokens()
 static var missing: Set<UUID> = []
 static func loadBlock(id:UUID)->BlockRule? {known.contains(id) && !missing.contains(id) ? BlockRule(id:id) : nil}
 static func loadGroups()->[QAGroup]? {[]}
 static func tokens(for block:BlockRule,groups:[QAGroup])->Tokens {selection}
}
enum BreakMonitoring {static func resetAllowance(blockID:UUID, stopMonitoring:Bool = true) {}}
@main struct Tests {
 static func main() {
  setbuf(stdout, nil)
  if CommandLine.arguments.count == 3, ["replace", "clear", "crash"].contains(CommandLine.arguments[1]) {
   let id = UUID(uuidString:CommandLine.arguments[2])!
   BlockResolution.known.insert(id)
   if CommandLine.arguments[1] == "crash" { NativeProbe.onWrite = { exit(0) } }
   if CommandLine.arguments[1] == "clear" { BlockingActuator.clearShields(blockID:id) }
   else { BlockingActuator.apply(tokens:.init(apps:[200]),blockID:id) }
   return
  }
  defer {SharedDefaults.suite.removePersistentDomain(forName:SharedDefaults.name)}
  var passed=0;var failed=0
  func check(_ yes:Bool,_ name:String){print("\(yes ? "PASS" : "FAIL"): \(name)");if yes {passed+=1}else{failed+=1}}
  let id=UUID(),other=UUID()
  BlockResolution.known.formUnion([id, other])
  for n in [0,1,49,50,51,99,100,101,399,400] {
   let apps=Set(0..<n),web=Set(1000..<(1000+n))
   BlockingActuator.apply(tokens:.init(apps:apps,categories:[9000],webDomains:web,domains:["example.com"]),blockID:id)
   var gotApps:Set<Int>=[],gotWeb:Set<Int>=[]
   for i in 0..<max(1,(n+49)/50) {
    let s=ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id,chunk:i));gotApps.formUnion(s.shield.applications ?? []);gotWeb.formUnion(s.shield.webDomains ?? [])
   }
   check(gotApps==apps && gotWeb==web,"mixed selection preserves all \(n) apps and web tokens")
  }
  BlockingActuator.apply(tokens:.init(apps:[1]),blockID:other)
  BlockingActuator.apply(tokens:.init(apps:[2]),blockID:id)
  check(ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id,chunk:7)).shield.applications==nil,"shrink clears old chunks")
  BlockingActuator.clearShields(blockID:id)
  check(SharedDefaults.suite.data(forKey: "shieldIntent.v1." + id.uuidString) != nil, "live-owner clear retains its durable tombstone")
  check(ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:other)).shield.applications==[1],"release one block preserves overlapping owner")
  ManagedSettingsStore.dropApps=true
  BlockingActuator.apply(tokens:.init(apps:[1]),blockID:id)
  check(SharedDefaults.suite.string(forKey:SharedDefaults.Keys.shieldAudit(blockID:id))?.contains("MISMATCH")==true,"dropped app writes are detected")
  ManagedSettingsStore.dropApps=false;ManagedSettingsStore.dropDomains=true
  BlockingActuator.apply(tokens:.init(domains:["example.com"]),blockID:id)
  check(SharedDefaults.suite.string(forKey:SharedDefaults.Keys.shieldAudit(blockID:id))?.contains("MISMATCH")==true,"dropped typed-domain writes are detected")
  ManagedSettingsStore.dropDomains=false
  BlockingActuator.apply(tokens:.init(apps:Set(0..<401)),blockID:id)
  check(SharedDefaults.suite.string(forKey:SharedDefaults.Keys.shieldError(blockID:id)) != nil,"selection truncation is surfaced as enforcement error")
  BlockingActuator.apply(tokens:.init(),blockID:id)
  check(SharedDefaults.suite.string(forKey:SharedDefaults.Keys.shieldError(blockID:id)) != nil,"empty target selection is not reported as blocked")
  check(NativeProbe.lockedCalls == 0, "ManagedSettings writes never hold the shared file lease (including nested transitions)")
  let outer = EnforcementTransaction.begin()!
  BlockingActuator.apply(tokens:.init(apps:[42]),blockID:id)
  outer.finish()
  let previous = NativeProbe.writes
  BlockingActuator.apply(tokens:.init(apps:[42]),blockID:id)
  check(NativeProbe.writes == previous, "unchanged successful shield state performs no native writes")
  check(NativeProbe.lockedCalls == 0, "outermost state transaction releases flock before shield IPC")
  let entered = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
  NativeProbe.onWrite = { entered.signal(); Thread.sleep(forTimeInterval: 2) }
  DispatchQueue.global().async {
   BlockingActuator.apply(tokens:.init(apps:[100]),blockID:id)
   finished.signal()
  }
  precondition(entered.wait(timeout: .now() + 5) == .success)
  let beforeStall = NativeProbe.lockedCalls
  // Separate open-file description tests the actual kernel flock, not recursion.
  NativeProbe.write()
  check(NativeProbe.lockedCalls == beforeStall, "two-second stalled native IPC leaves flock available")
  precondition(finished.wait(timeout: .now() + 5) == .success)
  NativeProbe.onWrite = {
   let child = Process()
   child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
   child.arguments = ["replace", id.uuidString]
   var environment = ProcessInfo.processInfo.environment
   environment["TYRI_SHIELD_SUITE"] = SharedDefaults.name
   environment["TYRI_TRANSACTION_PATH"] = environment["TYRI_TRANSACTION_PATH"] ?? NSTemporaryDirectory() + "tyri-enforcement-tests-\(ProcessInfo.processInfo.processIdentifier).lock"
   child.environment = environment
   try! child.run(); child.waitUntilExit()
   precondition(child.terminationStatus == 0)
  }
  BlockingActuator.apply(tokens:.init(apps:[101]),blockID:id)
  check(ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id)).shield.applications == [200],
        "late obsolete native write replays the newer cross-process intent")
  for command in ["replace", "clear"] {
   NativeProbe.onWrite = {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = [command, id.uuidString]
    var environment = ProcessInfo.processInfo.environment
    environment["TYRI_SHIELD_SUITE"] = SharedDefaults.name
    environment["TYRI_TRANSACTION_PATH"] = environment["TYRI_TRANSACTION_PATH"] ?? NSTemporaryDirectory() + "tyri-enforcement-tests-\(ProcessInfo.processInfo.processIdentifier).lock"
    child.environment = environment
    try! child.run(); child.waitUntilExit()
    precondition(child.terminationStatus == 0)
   }
   BlockingActuator.apply(tokens:.init(apps:Set(0..<400)),blockID:id)
   let first = ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id)).shield.applications
   let tail = ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id,chunk:7)).shield.applications
   check(tail == nil && first == (command == "clear" ? nil : [200]),
         "stale eight-chunk write cannot resurrect tails after newer \(command)")
  }
  let holding = DispatchSemaphore(value: 0), released = DispatchSemaphore(value: 0)
  let transition = EnforcementTransaction.begin()!
  EnforcementTransaction.afterUnlock(key:"contention-fixture") {
   DispatchQueue.global().async {
    let competing = EnforcementTransaction.begin()!
    holding.signal()
    Thread.sleep(forTimeInterval: 0.2)
    competing.finish()
    released.signal()
   }
   precondition(holding.wait(timeout: .now() + 5) == .success)
  }
  BlockingActuator.apply(tokens:.init(apps:[203]),blockID:id)
  transition.finish()
  precondition(released.wait(timeout: .now() + 5) == .success)
  check(ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id)).shield.applications == [203],
        "extension effect retries transient post-unlock contention without another callback")
  // Resign during a native write: no subsequent property call may start.
  var stoppedAt = 0
  NativeProbe.onWrite = {
   stoppedAt = NativeProbe.writes
   BlockingActuator.setEffectsEnabled(false)
  }
  BlockingActuator.apply(tokens:.init(apps:[202]),blockID:id)
  check(NativeProbe.writes == stoppedAt, "native call returning after inactivity starts no further IPC")
  BlockingActuator.setEffectsEnabled(true)
  BlockingActuator.replayPending()
  check(ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id)).shield.applications == [202],
        "interrupted native operation remains repairable on activation")
  BlockingActuator.setEffectsEnabled(false)
  let beforeBackground = NativeProbe.writes
  BlockingActuator.apply(tokens:.init(apps:[201]),blockID:id)
  check(NativeProbe.writes == beforeBackground, "background admits no new native shield effects")
  BlockingActuator.setEffectsEnabled(true)
  BlockingActuator.replayPending()
  check(ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id)).shield.applications == [201],
        "foreground repairs intent persisted while inactive")
  BlockingActuator.setEffectsEnabled(false)
  BlockingActuator.clearShields(blockID:id)
  BlockingActuator.setEffectsEnabled(true)
  BlockingActuator.replayPending()
  check(ManagedSettingsStore(named:BlockingActuator.appsStoreName(for:id)).shield.applications == nil,
        "foreground replays a pending clear even when its block/session was deleted")
  let crashedID = UUID()
  BlockResolution.known.insert(crashedID)
  let child = Process()
  child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
  child.arguments = ["crash", crashedID.uuidString]
  var environment = ProcessInfo.processInfo.environment
  environment["TYRI_SHIELD_SUITE"] = SharedDefaults.name
  environment["TYRI_TRANSACTION_PATH"] = environment["TYRI_TRANSACTION_PATH"] ?? NSTemporaryDirectory() + "tyri-enforcement-tests-\(ProcessInfo.processInfo.processIdentifier).lock"
  child.environment = environment
  try! child.run(); child.waitUntilExit()
  precondition(child.terminationStatus == 0)
  BlockingActuator.apply(tokens:.init(apps:[200]),blockID:crashedID)
  let afterRepair = NativeProbe.writes
  BlockingActuator.apply(tokens:.init(apps:[200]),blockID:crashedID)
  check(NativeProbe.writes == afterRepair, "dead writer receipt retires and unchanged recovered shield settles")
  BlockResolution.missing.insert(crashedID)
  BlockingActuator.clearShields(blockID: crashedID)
  check(SharedDefaults.suite.data(forKey: "shieldIntent.v1." + crashedID.uuidString) == nil,
        "successful deleted-owner clear compacts tombstone after all writers finish")
  precondition(failed == 0, "Shield regressions")
  print("RESULT: \(passed) passed, \(failed) failed — production actuator with deterministic settings double")
 }
}
