import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<T> { var wrappedValue: T }
struct FamilyActivitySelection: Codable {}
enum BlockType: Codable { case schedule }
struct BlockRule: Codable { var id = UUID(); var name: String; var type: BlockType = .schedule; var isEnabled = false; var appGroupIDs: [UUID] = [] }
struct AppGroup: Codable { var id = UUID(); var name: String; var updatedAt = Date(); var selection = FamilyActivitySelection() }
enum SharedDefaults {
 static let suite = UserDefaults(suiteName: "tyri-store-durability-\(UUID())")!
 enum Keys {
  static let blocks = "blocks", groups = "groups"
  static func manualActivation(blockID: UUID) -> String { "activation.\(blockID)" }
  static func cooldownEnd(blockID: UUID) -> String { "cooldown.\(blockID)" }
  static func cooldownActivation(blockID: UUID) -> String { "cooldownActivation.\(blockID)" }
  static func running(blockID: UUID) -> String { "running.\(blockID)" }
  static func usageLockEnd(blockID: UUID) -> String { "lock.\(blockID)" }
  static func usageError(blockID: UUID) -> String { "error.\(blockID)" }
  static func usageLockError(blockID: UUID) -> String { "lockerror.\(blockID)" }
  static func usageGeneration(blockID: UUID) -> String { "generation.\(blockID)" }
  static func shieldError(blockID: UUID) -> String { "shield.\(blockID)" }
 }
}
enum UsageProgress { static func key(_ id: UUID) -> String { "progress.\(id)" } }
enum EnforcementDiagnostics { static let events: [String] = []; static func key(_ event: String, _ id: UUID) -> String { event } }
@main struct Tests {
 @MainActor static func main() throws {
  let bytes = Data("{unknown future schema".utf8)
  SharedDefaults.suite.set(bytes, forKey: "blocks"); SharedDefaults.suite.set(bytes, forKey: "groups")
  let blocks = BlockStore.shared, groups = AppGroupStore.shared
  blocks.flush(); groups.flush()
  precondition(SharedDefaults.suite.data(forKey: "blocks") == bytes, "Unreadable saved rules overwritten")
  precondition(SharedDefaults.suite.data(forKey: "groups") == bytes, "Unreadable saved lists overwritten")
  precondition(blocks.loadError != nil && groups.loadError != nil)
  blocks.insert(BlockRule(name: "Should not replace data")); groups.insert(AppGroup(name: "Should not replace data"))
  blocks.flush(); groups.flush()
  precondition(SharedDefaults.suite.data(forKey: "blocks") == bytes && SharedDefaults.suite.data(forKey: "groups") == bytes)
  let block = BlockRule(name: "Recovered"), group = AppGroup(name: "Recovered list")
  SharedDefaults.suite.set(try JSONEncoder().encode([block]), forKey: "blocks")
  SharedDefaults.suite.set(try JSONEncoder().encode([group]), forKey: "groups")
  blocks.reload(); groups.reload()
  precondition(blocks.loadError == nil && groups.loadError == nil)
  blocks.flush(); groups.flush()
  precondition(blocks.blocks.first?.id == block.id && groups.groups.first?.id == group.id)
  print("PASS: unreadable current stores survive launch/flush/edit; successful reload preserves identities and restores writes")
 }
}
