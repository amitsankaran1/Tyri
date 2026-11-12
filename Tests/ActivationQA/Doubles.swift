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
class Breaks {func restoreActiveBreaksIfAny(){}}
class AdHoc {func refresh(){}}
// This probe covers HomeView's dispatch boundary. Registration and authorization
// are exercised by ForegroundRecoveryQA, using the production worker.
class ForegroundRecovery {
 static let shared=ForegroundRecovery()
 var requests=0
 var onRequest:(()->Void)?
 func request(){requests+=1;onRequest?()}
}
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
 var screenTime:Screen{screenTimeManager};var usage:Usage{usageLimitManager};var scheduling:Scheduling{schedulingManager};let adHoc=AdHoc();let breaks=Breaks()
 var blockID:UUID{blockStore.value.id}
 var hasLoaded=true;var newBlock:BlockRule?=nil;var type:BlockType = .timer;var schedule:Int?=nil;var usageLimitMinutes=5,usageLockMinutes=5,cooldownMinutes=5,breakMinutes=0;var groupIDs:Set<UUID>=[UUID()];var isEnabled=true;var name="Timer";var finished=false
 func finish(){finished=true}
}
@main struct Tests {
 @MainActor static func main() async {
  let p=Probe();var synchronousRegistrations=0;var readyAtRecovery=false
  p.usageLimitManager.onRegister={synchronousRegistrations+=1}
  let beforeSave=ForegroundRecovery.shared.requests
  await withCheckedContinuation { (done:CheckedContinuation<Void,Never>) in
   ForegroundRecovery.shared.onRequest={
    readyAtRecovery=p.screenTimeManager.shield && p.finished && p.blockStore.value.isEnabled
    done.resume()
   }
   p.save()
   print("\(synchronousRegistrations==0 && ForegroundRecovery.shared.requests==beforeSave && p.finished ? "PASS" : "FAIL"): Save returns without synchronous monitor registration")
  }
  print("\(ForegroundRecovery.shared.requests==beforeSave+1 && readyAtRecovery ? "PASS" : "FAIL"): deferred recovery observes the persisted block and manual shield after Save returns")
  ForegroundRecovery.shared.onRequest=nil
  print("\(p.screenTimeManager.shield ? "PASS" : "FAIL"): manual shield applied after successful save")
  let edited=Probe();edited.isEnabled=false
  edited.blockStore.value.usageLimitMinutes=15;edited.usageLimitMinutes=10
  var editedRegisters=0;var savedEditAtRecovery=false
  edited.usageLimitManager.onRegister={editedRegisters+=1}
  let beforeEdit=ForegroundRecovery.shared.requests
  await withCheckedContinuation { (done:CheckedContinuation<Void,Never>) in
   ForegroundRecovery.shared.onRequest={
    savedEditAtRecovery=edited.finished && edited.blockStore.value.usageLimitMinutes==10
    done.resume()
   }
   edited.save()
   print("\(edited.finished && editedRegisters==0 && edited.blockStore.value.usageLimitMinutes==10 && ForegroundRecovery.shared.requests==beforeEdit ? "PASS" : "FAIL"): editing a limit from 15 to 10 persists and returns before monitor work")
  }
  print("\(ForegroundRecovery.shared.requests==beforeEdit+1 && savedEditAtRecovery ? "PASS" : "FAIL"): edited limit queues recovery after persistence")
  ForegroundRecovery.shared.onRequest=nil
  p.usageLimitManager.active=false
  let requests=ForegroundRecovery.shared.requests;p.refresh()
  print("\(ForegroundRecovery.shared.requests==requests+1 && !p.usageLimitManager.active ? "PASS" : "FAIL"): foreground queues recovery without synchronous monitor registration")
  let denied=Probe();denied.screenTimeManager.authorizationStatus = .denied;denied.save()
  print("\(!denied.screenTimeManager.shield && denied.validationError != nil ? "PASS" : "FAIL"): Block now rejects missing authorization explicitly")
  let empty=Probe();BlockResolution.empty=true;empty.save();BlockResolution.empty=false
  print("\(!empty.screenTimeManager.shield && empty.validationError != nil ? "PASS" : "FAIL"): Block now rejects empty targets explicitly")
  let revoked=Probe();revoked.screenTime.authorizationStatus = .denied;revoked.usage.active=false;revoked.refresh()
  print("\(revoked.usage.starts==0 ? "PASS" : "FAIL"): foreground never registers synchronously when authorization is revoked")
  let starts=p.usageLimitManager.starts;p.refresh()
  print("\(starts==p.usageLimitManager.starts ? "PASS" : "FAIL"): foreground preserves a healthy monitor")
 }
}

extension ForegroundRecovery { func finish(_ lease: EnforcementTransaction.Lease) { lease.finish() }; func requestAccepted() { Task { @MainActor in self.request() } } }

extension Probe { var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !groupIDs.isEmpty } }
