import Foundation
struct Schedule {func activeWindow()->DateInterval?{nil};var summary="Schedule"}
struct BlockRule {enum Kind{case timer,schedule,tag};var id=UUID();var type:Kind = .timer;var isEnabled=false;var schedule:Schedule?;var usageLimitMinutes:Int?=30;var usageLockMinutes=180}
enum SharedDefaults {static let suite=UserDefaults(suiteName:"tyri-status-\(UUID())")!;enum Keys{static func shieldError(blockID:UUID)->String{"shield.\(blockID)"};static func usageError(blockID:UUID)->String{"usage.\(blockID)"};static func usageLockError(blockID:UUID)->String{"lock.\(blockID)"}}}
@MainActor class ScreenTimeManager {enum Authorization {case approved,denied};static let shared=ScreenTimeManager();var authorizationStatus:Authorization = .approved;var active=false;func isBlockActive(_ b:BlockRule)->Bool{active}}
@MainActor class SchedulingManager {static let shared=SchedulingManager();var registrationErrors:[UUID:String]=[:]}
@MainActor class UsageLimitManager {static let shared=UsageLimitManager();func lockEnd(for id:UUID)->Date?{nil}}
@MainActor class CooldownManager {struct Active{var blockID:UUID;var endsAt:Date};static let shared=CooldownManager();var activeCooldown:Active?}
enum BreakMonitoring {static var paused=false;static func isOnBreak(blockID:UUID)->Bool{paused};static func breakEnd(blockID:UUID)->Date?{Date().addingTimeInterval(300)}}
enum UsageMonitoring {static var registered=true;static func isUsageMonitorActive(for id:UUID)->Bool{registered}}
enum UsageProgress {static func reported(blockID:UUID)->Int?{5};static func step(for limit:Int)->Int{1}}
enum BlockingEndDescription {static func detail(timedEnd:Date?,manual:Bool,tag:Bool)->String{"Active"}}
@main struct Tests {
 @MainActor static func main(){
  let b=BlockRule();var n=0
  func check(_ yes:Bool,_ name:String){precondition(yes,name);n+=1}
  check(BlockStatusPresentation.current(for:b).state == .tracking,"healthy timer remains tracking")
  ScreenTimeManager.shared.active=true
  for key in [SharedDefaults.Keys.shieldError(blockID:b.id),SharedDefaults.Keys.usageLockError(blockID:b.id),SharedDefaults.Keys.usageError(blockID:b.id)] {
   SharedDefaults.suite.set("",forKey:key)
   let status=BlockStatusPresentation.current(for:b)
   check(status.state == .unavailable && !status.detail.isEmpty,"active owner must expose error and fallback explanation")
   SharedDefaults.suite.removeObject(forKey:key)
  }
  SchedulingManager.shared.registrationErrors[b.id]=""
  check(BlockStatusPresentation.current(for:b).state == .unavailable,"schedule registration error remains visible")
  SchedulingManager.shared.registrationErrors=[:]
  BreakMonitoring.paused=true
  check(BlockStatusPresentation.current(for:b).state == .paused,"healthy break retains paused state")
  ScreenTimeManager.shared.authorizationStatus = .denied
  check(BlockStatusPresentation.current(for:b).state == .setup,"permission recovery takes precedence")
  ScreenTimeManager.shared.authorizationStatus = .approved;ScreenTimeManager.shared.active=false;BreakMonitoring.paused=false;UsageMonitoring.registered=false
  check(BlockStatusPresentation.current(for:b).state == .unavailable,"missing monitor requires recovery")
  print("PASS: \(n) production recovery-presentation checks")
 }
}
