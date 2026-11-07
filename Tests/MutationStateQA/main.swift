import Foundation
struct Schedule {var active=true;func activeWindow()->Int?{active ? 1:nil}}
struct BlockRule {enum Kind{case timer,schedule,tag};var id=UUID();var type:Kind = .timer;var appGroupIDs:[UUID]=[];var isEnabled=false;var schedule:Schedule?}
enum SharedDefaults {static let suite=UserDefaults(suiteName:"tyri-mutation-\(UUID())")!;enum Keys{static func running(blockID:UUID)->String{"running.\(blockID)"};static func usageLockEnd(blockID:UUID)->String{"lock.\(blockID)"};static func scheduleReleasedUntil(blockID:UUID)->String{"release.\(blockID)"}}}
class BlockStore {
 static let shared=BlockStore();var blocks:[BlockRule]=[],persisted:[BlockRule]=[]
 func block(id:UUID)->BlockRule?{blocks.first{$0.id==id}}
 func setEnabled(id:UUID,enabled:Bool){if var b=block(id:id){b.isEnabled=enabled;update(b)}}
 func update(_ b:BlockRule){blocks.removeAll{$0.id==b.id};blocks.append(b)}
 func delete(id:UUID){blocks.removeAll{$0.id==id}}
 func flush(){persisted=blocks}
}
class GroupStore {func delete(id:UUID){};func flush(){}}
class ScreenTimeManager {static let shared=ScreenTimeManager();func clearBlockShield(id:UUID){}}
enum ScheduleEnforcement {static func releaseCurrentWindow(block:BlockRule){}}
enum UsageMonitoring {static func stopLockout(for id:UUID){SharedDefaults.suite.removeObject(forKey:SharedDefaults.Keys.usageLockEnd(blockID:id))}}
class UsageLimitManager {
 static let shared=UsageLimitManager();var monitors:Set<UUID>=[];var applied:[BlockRule]=[]
 func applyUsageLimit(for b:BlockRule,forceReset:Bool){applied.append(b);if b.appGroupIDs.isEmpty{monitors.remove(b.id)}else{monitors.insert(b.id)}}
 func reapplyAllUsageLimits(){for b in BlockStore.shared.blocks where b.type == .timer && !monitors.contains(b.id){applyUsageLimit(for:b,forceReset:false)}}
 func removeUsageLimit(for b:BlockRule){monitors.remove(b.id)};func refresh(){}
}
class SchedulingManager {static let shared=SchedulingManager();var deletionSawPersistedRule=false;func refresh(){};func removeSchedule(for b:BlockRule){deletionSawPersistedRule=BlockStore.shared.persisted.contains{$0.id==b.id}}}
class CooldownManager {static let shared=CooldownManager();func cancel(){}}
enum AdHocMonitoring {struct Session{var id=UUID()};static var session:Session?;static func finish(id:UUID){session=nil}}
class AdHocManager {static let shared=AdHocManager();func refresh(){}}
class GroupEditor {var groupID=UUID();var activeReferencingBlocks:[BlockRule]=[];var showActiveDeleteAlert=false;let blockStore=BlockStore.shared,groupStore=GroupStore(),usageLimitManager=UsageLimitManager.shared;func finish(){}}
class BlockEditor {var blockID=UUID();var showActiveDeleteAlert=false;let blockStore=BlockStore.shared,screenTimeManager=ScreenTimeManager.shared,schedulingManager=SchedulingManager.shared,usageLimitManager=UsageLimitManager.shared;func finish(){}}
@main struct Tests {
 static func main(){
  var failures=0
  func check(_ yes:Bool,_ name:String){print("\(yes ? "PASS":"FAIL"): \(name)");if !yes{failures+=1}}
  let g=GroupEditor();let remaining=UUID();var b=BlockRule(appGroupIDs:[g.groupID,remaining]);BlockStore.shared.blocks=[b];BlockStore.shared.flush();UsageLimitManager.shared.monitors=[b.id]
  g.deleteGroup()
  check(UsageLimitManager.shared.applied.last?.appGroupIDs == [remaining],"SM-02 deleting one list replaces monitor with remaining selection")
  check(BlockStore.shared.persisted.first?.appGroupIDs == [remaining],"SM-02 deletion publishes detached references synchronously")
  g.groupID=remaining;g.deleteGroup();check(!UsageLimitManager.shared.monitors.contains(b.id),"SM-02 deleting last list stops old usage monitor")
  let e=BlockEditor();b=BlockRule(id:e.blockID,type:.tag);BlockStore.shared.blocks=[b];BlockStore.shared.flush();e.deleteBlock()
  check(!SchedulingManager.shared.deletionSawPersistedRule,"SM-02 rule deletion precedes monitor-stop callbacks")
  let timer=BlockRule(appGroupIDs:[remaining],isEnabled:true);BlockStore.shared.blocks=[timer];BlockStore.shared.flush();UsageLimitManager.shared.monitors=[]
  SharedDefaults.suite.set(Date().addingTimeInterval(300),forKey:SharedDefaults.Keys.usageLockEnd(blockID:timer.id))
  ScreenTimeManager.shared.disableAllBlocks()
  check(UsageLimitManager.shared.monitors.contains(timer.id),"SM-03 emergency release rearms consumed timer allowance")
  check(BlockStore.shared.persisted.first?.isEnabled == false,"SM-03 emergency release commits manual-off before returning")
  let scheduled=BlockRule(type:.schedule,schedule:Schedule())
  check(ScreenTimeManager.shared.isBlockActive(scheduled),"SM-06 calendar ownership protects edits before start callback arrives")
  var ended=scheduled;ended.schedule=Schedule(active:false);SharedDefaults.suite.set(true,forKey:SharedDefaults.Keys.running(blockID:ended.id))
  check(!ScreenTimeManager.shared.isBlockActive(ended),"SM-06 stale running flag cannot keep expired schedule logically active")
  if failures>0{exit(1)}
 }
}
