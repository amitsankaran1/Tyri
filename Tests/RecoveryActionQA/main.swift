import Foundation
enum SharedDefaults {static let suite=UserDefaults(suiteName:"tyri-retry-\(UUID())")!}
struct BlockRule {enum Kind{case timer,schedule,tag};var id=UUID();var type:Kind = .timer}
@MainActor class ScreenTimeManager {
 enum Authorization{case approved,denied};static let shared=ScreenTimeManager()
 var authorizationStatus:Authorization = .approved;var updates=0
 func checkAuthorizationStatus(){};func updateBlockShieldIfActive(_ block:BlockRule){updates+=1}
}
@MainActor class BlockStore {static let shared=BlockStore();var value:BlockRule?;func block(id:UUID)->BlockRule?{value?.id==id ? value:nil}}
@MainActor class UsageLimitManager {static let shared=UsageLimitManager();var resets:[Bool]=[];func applyUsageLimit(for block:BlockRule,forceReset:Bool){resets.append(forceReset)};func refresh(){}}
@MainActor class SchedulingManager {static let shared=SchedulingManager();var registrations=0;func applySchedule(for block:BlockRule){registrations+=1};func refresh(){}}
@main struct Tests {
 @MainActor static func main(){
  var b=BlockRule();BlockStore.shared.value=b
  precondition(BlockingRecovery.retry(blockID:b.id))
  precondition(UsageLimitManager.shared.resets == [false],"retry must preserve healthy allowance")
  ScreenTimeManager.shared.authorizationStatus = .denied
  precondition(!BlockingRecovery.retry(blockID:b.id) && UsageLimitManager.shared.resets.count==1,"permission denial must not mutate registration")
  ScreenTimeManager.shared.authorizationStatus = .approved
  precondition(!BlockingRecovery.retry(blockID:UUID()),"deleted block cannot be repaired from a stale draft")
  b.type = .schedule;BlockStore.shared.value=b
  precondition(BlockingRecovery.retry(blockID:b.id) && SchedulingManager.shared.registrations==1,"schedule retry repairs schedule")
  b.type = .tag;BlockStore.shared.value=b
  precondition(BlockingRecovery.retry(blockID:b.id) && UsageLimitManager.shared.resets.count==1,"tag repair does not change timers")
  print("PASS: 5 recovery action contracts against production retry service")
 }
}

final class ForegroundRecovery { static let shared = ForegroundRecovery(); func request() {} }

extension ForegroundRecovery { func finish(_ lease: EnforcementTransaction.Lease) { lease.finish() }; func requestAccepted() { request() } }
