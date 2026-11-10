import Foundation
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
  var applications: Set<Int>? { didSet { if let v=applications, v.count > 50 || ManagedSettingsStore.dropApps { applications=nil } } }
  var applicationCategories: Policy?
  var webDomains: Set<Int>? { didSet { if let v=webDomains, v.count > 50 { webDomains=nil } } }
 }
 class WebContent { var blockedByFilter: Filter? { didSet { if ManagedSettingsStore.dropDomains { blockedByFilter=nil } } } }
 static var dropApps=false, dropDomains=false
 static var saved: [Name: ManagedSettingsStore] = [:]
 var shield=Shield();var webContent=WebContent()
 init() {}
 convenience init(named name: Name) { self.init();if let old=Self.saved[name] { shield=old.shield;webContent=old.webContent } else {Self.saved[name]=self} }
 func clearAllSettings() { shield.applications=nil;shield.webDomains=nil;shield.applicationCategories=nil;webContent.blockedByFilter=nil }
}
enum SharedDefaults {
 static let name="tyri-shield-tests-\(UUID())"
 static let suite=UserDefaults(suiteName:name)!
 enum Keys {
  static func running(blockID:UUID)->String {"running.\(blockID)"}
  static func shieldChunkCount(blockID:UUID)->String {"chunks.\(blockID)"}
  static func shieldAudit(blockID:UUID)->String {"audit.\(blockID)"}
  static func shieldError(blockID:UUID)->String {"shieldError.\(blockID)"}
 }
}
struct BlockRule { enum Kind {case schedule,timer};let id:UUID;var type:Kind = .timer;var schedule:Schedule?=nil }
struct Schedule {var weekdays:Set<Int>=[]}
enum BlockResolution {
 struct Tokens {var apps:Set<Int>=[];var categories:Set<Int>=[];var webDomains:Set<Int>=[];var domains:Set<String>=[]}
 static var selection=Tokens()
 static func loadBlock(id:UUID)->BlockRule? {BlockRule(id:id)}
 static func loadGroups()->[Int] {[]}
 static func tokens(for block:BlockRule,groups:[Int])->Tokens {selection}
}
enum BreakMonitoring {static func resetAllowance(blockID:UUID) {}}
@main struct Tests {
 static func main() {
  defer {SharedDefaults.suite.removePersistentDomain(forName:SharedDefaults.name)}
  var passed=0;var failed=0
  func check(_ yes:Bool,_ name:String){print("\(yes ? "PASS" : "FAIL"): \(name)");if yes {passed+=1}else{failed+=1}}
  let id=UUID(),other=UUID()
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
  print("RESULT: \(passed) passed, \(failed) failed — production actuator with deterministic settings double")
 }
}
