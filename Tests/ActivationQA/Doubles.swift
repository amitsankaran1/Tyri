import Foundation
enum BlockType { case timer,schedule,tag }
struct BlockRule { var id=UUID();var name="Timer";var type:BlockType = .timer;var appGroupIDs:[UUID]=[UUID()];var cooldownMinutes=5;var breakMinutes=0;var isEnabled=false;var schedule:Int?=nil;var usageLimitMinutes:Int?=5;var usageLockMinutes=5 }
class Store {
 var value=BlockRule()
 func block(id:UUID)->BlockRule?{value}
 func insert(_ b:BlockRule){value=b}
 func update(_ b:BlockRule){value=b}
 func flush(){}
}
enum Authorization {case approved,denied}
class Screen {
 var authorizationStatus: Authorization = .approved
 var shield=false
 func isBlockActive(_ b:BlockRule)->Bool{b.isEnabled}
 func applyBlockShield(_ b:BlockRule){shield=true}
 func clearBlockShield(id:UUID){shield=false}
 func updateBlockShieldIfActive(_ b:BlockRule){if b.isEnabled{shield=true}}
 func checkAuthorizationStatus(){}
 func restoreBlockingIfNeeded(){}
}
class Usage {
 var active=true,starts=0;var onRegister:(()->Void)?
 func removeUsageLimit(for b:BlockRule){}
 func applyUsageLimit(for b:BlockRule,forceReset:Bool){onRegister?()}
 func lockEnd(for id:UUID)->Date?{nil}
 func reconcileExpiredLocks(){}
 func reapplyAllUsageLimits(){if !active{starts+=1;active=true}}
}
class Scheduling {
 var registrationErrors:[UUID:String]=[:]
 func removeSchedule(for b:BlockRule){}
 func applySchedule(for b:BlockRule){}
 func refresh(){}
 func repairMissingSchedules(){}
}
class AdHoc {func refresh(){}}
enum SharedDefaults {static let suite=UserDefaults(suiteName:"activation-tests-\(UUID())")!;enum Keys {static func running(blockID:UUID)->String{"running.\(blockID)"}}}
enum BreakMonitoring {static func resetAllowance(blockID:UUID){}}
enum BlockResolution {
 static var empty=false
 struct Tokens { var isEmpty:Bool;var domains:Set<String>=[] }
 static func tokens(for block:BlockRule,groups:[Int])->Tokens {Tokens(isEmpty:empty)}
}
class GroupStore {var groups:[Int]=[]}
class Probe {
 let groupStore=GroupStore();var validationError:String?
 let blockStore=Store(),screenTimeManager=Screen(),usageLimitManager=Usage(),schedulingManager=Scheduling()
 var screenTime:Screen{screenTimeManager};var usage:Usage{usageLimitManager};var scheduling:Scheduling{schedulingManager};let adHoc=AdHoc()
 var blockID:UUID{blockStore.value.id}
 var hasLoaded=true;var newBlock:BlockRule?=nil;var type:BlockType = .timer;var schedule:Int?=nil;var usageLimitMinutes=5,usageLockMinutes=5,cooldownMinutes=5,breakMinutes=0;var groupIDs:Set<UUID>=[];var isEnabled=true;var name="Timer";var finished=false
 func finish(){finished=true}
}
@main struct Tests {
 static func main(){
  let p=Probe();var shieldBeforeRegistration=false
  p.usageLimitManager.onRegister={shieldBeforeRegistration=p.screenTimeManager.shield}
  p.save()
  print("\(shieldBeforeRegistration ? "PASS" : "FAIL"): manual shield exists before potentially blocking monitor registration")
  print("\(p.screenTimeManager.shield ? "PASS" : "FAIL"): manual shield applied after successful save")
  p.usageLimitManager.active=false;p.refresh()
  print("\(p.usageLimitManager.active ? "PASS" : "FAIL"): foreground repairs a lost usage monitor")
  let denied=Probe();denied.screenTimeManager.authorizationStatus = .denied;denied.save()
  print("\(!denied.screenTimeManager.shield && denied.validationError != nil ? "PASS" : "FAIL"): Block now rejects missing authorization explicitly")
  let empty=Probe();BlockResolution.empty=true;empty.save();BlockResolution.empty=false
  print("\(!empty.screenTimeManager.shield && empty.validationError != nil ? "PASS" : "FAIL"): Block now rejects empty targets explicitly")
  let revoked=Probe();revoked.screenTime.authorizationStatus = .denied;revoked.usage.active=false;revoked.refresh()
  print("\(revoked.usage.starts==0 ? "PASS" : "FAIL"): foreground does not register without authorization")
  let starts=p.usageLimitManager.starts;p.refresh()
  print("\(starts==p.usageLimitManager.starts ? "PASS" : "FAIL"): foreground preserves a healthy monitor")
 }
}
