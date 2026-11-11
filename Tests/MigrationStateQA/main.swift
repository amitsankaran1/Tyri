import Foundation
struct FamilyActivitySelection:Codable {var includeEntireCategory=false;var applicationTokens:Set<Int>=[];var categoryTokens:Set<Int>=[];var webDomainTokens:Set<Int>=[]}
enum SharedDefaults {static let suite=UserDefaults(suiteName:"tyri-migration-\(UUID())")!;enum Keys{static let presets="presets",migratedToBlocksV2="migrated"}}
struct ManagedSettingsStore {struct Name{var rawValue:String};init(){};init(named:Name){};func clearAllSettings(){}}
struct DeviceActivityName {var rawValue:String}
struct DeviceActivityCenter {func stopMonitoring(_ names:[DeviceActivityName]){}}
enum BlockingActuator {@discardableResult static func start(blockID:UUID,bypassWeekday:Bool,setRunningFlag:Bool,resetBreakAllowance:Bool = true)->Bool{true}}
final class ForegroundRecovery {static let shared=ForegroundRecovery();func retireLegacy(_ names:[String]){}}
@MainActor class AppConfigurationStore {static let shared=AppConfigurationStore();var selectedApps=FamilyActivitySelection();var isBlockingEnabled=false}
@MainActor class AppGroupStore {static let shared=AppGroupStore();var groups:[AppGroup]=[];func replaceAll(_ v:[AppGroup]){groups=v}}
@MainActor class BlockStore {static let shared=BlockStore();var blocks:[BlockRule]=[];func replaceAll(_ v:[BlockRule]){blocks=v}}
@main struct Tests {
 @MainActor static func main() throws {
  var failures=0
  func check(_ yes:Bool,_ name:String){print("\(yes ? "PASS":"FAIL"): \(name)");if !yes{failures+=1}}
  let data=try JSONSerialization.data(withJSONObject:[["id":UUID().uuidString,"name":"Legacy manual","isEnabled":true]])
  SharedDefaults.suite.set(data,forKey:SharedDefaults.Keys.presets)
  Migration.runIfNeeded()
  check(BlockStore.shared.blocks.first?.isEnabled == true,"SM-05 migration preserves active manual ownership")
  let groupIDs=AppGroupStore.shared.groups.map(\.id),blockIDs=BlockStore.shared.blocks.map(\.id)
  // Exact persisted cut after group write, before block write / completion marker.
  BlockStore.shared.blocks=[]
  SharedDefaults.suite.set(false,forKey:SharedDefaults.Keys.migratedToBlocksV2)
  SharedDefaults.suite.set(data,forKey:SharedDefaults.Keys.presets)
  Migration.runIfNeeded()
  check(AppGroupStore.shared.groups.map(\.id)==groupIDs && BlockStore.shared.blocks.map(\.id)==blockIDs,"SM-05 interrupted migration retries without duplicate lists or new identities")
  // Cut after both writes, before completion marker.
  SharedDefaults.suite.set(false,forKey:SharedDefaults.Keys.migratedToBlocksV2)
  SharedDefaults.suite.set(data,forKey:SharedDefaults.Keys.presets)
  Migration.runIfNeeded()
  check(AppGroupStore.shared.groups.count==1 && BlockStore.shared.blocks.count==1,"SM-05 retry after both writes is idempotent")
  SharedDefaults.suite.set(false,forKey:SharedDefaults.Keys.migratedToBlocksV2)
  let corrupt=Data("unreadable".utf8);SharedDefaults.suite.set(corrupt,forKey:SharedDefaults.Keys.presets)
  Migration.runIfNeeded()
  check(!SharedDefaults.suite.bool(forKey:SharedDefaults.Keys.migratedToBlocksV2) && SharedDefaults.suite.data(forKey:SharedDefaults.Keys.presets)==corrupt,"SM-05 undecodable input retained for recovery, never marked migrated")
  if failures>0{exit(1)}
 }
}

extension ForegroundRecovery { func finish(_ lease: EnforcementTransaction.Lease) { lease.finish() }; func requestAccepted() {} }
