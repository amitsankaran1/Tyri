import Foundation
protocol ObservableObject {}
final class ForegroundRecovery {
    static let shared = ForegroundRecovery()
    func request() {}
}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct DeviceActivityName: Hashable { var rawValue: String }
struct DeviceActivitySchedule {}
struct DeviceActivityCenter {
    static var registered: Set<DeviceActivityName> = []
    static var starts = 0
    var activities: [DeviceActivityName] { Array(Self.registered) }
    static var failNext = false
    func startMonitoring(_ name: DeviceActivityName, during: DeviceActivitySchedule) throws {
        if Self.failNext || (!Self.registered.contains(name) && Self.registered.count >= 20) { Self.failNext = false; throw NSError(domain: "QA", code: 1) }
        Self.starts += 1; Self.registered.insert(name)
    }
    func stopMonitoring(_ names: [DeviceActivityName]) { for n in names { Self.registered.remove(n) } }
}
struct BlockingSchedule {
    enum CrossingSegment { case full, early, late }
    func deviceActivitySchedule() -> DeviceActivitySchedule { .init() }
}
enum BlockType { case schedule }
struct BlockRule {
    let id = UUID()
    var name: String
    let type = BlockType.schedule
    var schedule: BlockingSchedule? = .init()
}
enum SharedDefaults {
    static let suite = UserDefaults(suiteName: "tyri-schedule-qa-\(UUID())")!
    enum Keys {
        static func running(blockID: UUID) -> String { "run.\(blockID)" }
        static func scheduleWindowStart(blockID: UUID) -> String { "start.\(blockID)" }
        static func scheduleReleasedUntil(blockID: UUID) -> String { "release.\(blockID)" }
    }
}
enum ScheduleEnforcement {
    static func reconcile(block: BlockRule) {}
    static func registrationContext(_ schedule: BlockingSchedule) -> String { "schedule" }
}
@MainActor final class BlockStore {
    static let shared = BlockStore()
    var blocks: [BlockRule] = []
}
@main struct Tests {
    @MainActor static func main() {
        let manager = SchedulingManager.shared
        let first = BlockRule(name: "First")
        let second = BlockRule(name: "Second")
        precondition(manager.applySchedule(for: first))
        precondition(manager.applySchedule(for: second))
        precondition(DeviceActivityCenter.starts == 0, "Save must not perform native registration on MainActor")
        manager.publishRecovery(errors: [first.id: "Unavailable"])
        precondition(manager.registrationErrors[first.id] != nil)
        manager.removeSchedule(for: first)
        precondition(manager.registrationErrors[first.id] == nil)
        manager.repairMissingSchedules()
        precondition(DeviceActivityCenter.starts == 0, "Repair must use the shared worker")
        manager.setForegroundActive(true)
        let timer = manager.refreshTimer!
        precondition(timer.isValid)
        manager.setForegroundActive(false)
        precondition(!timer.isValid && manager.refreshTimer == nil, "Background left the periodic timer active")
        manager.setForegroundActive(true)
        precondition(manager.refreshTimer?.isValid == true, "Foreground failed to restart periodic recovery")
        manager.setForegroundActive(false)
        print("PASS: actual periodic schedule timer stops on background and restarts on activation")
        print("PASS: schedule Save/repair dispatch and error publication against production manager")
    }
}

extension ForegroundRecovery { func finish(_ lease: EnforcementTransaction.Lease) { lease.finish() }; func requestAccepted() { request() } }
