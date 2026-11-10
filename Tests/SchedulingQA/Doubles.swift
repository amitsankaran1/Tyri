import Foundation
protocol ObservableObject {}
@MainActor final class ForegroundRecovery {
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
        if Self.failNext { Self.failNext = false; throw NSError(domain: "QA", code: 1) }
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
enum ScheduleEnforcement { static func reconcile(block: BlockRule) {} }
@MainActor final class BlockStore {
    static let shared = BlockStore()
    var blocks: [BlockRule] = []
}
@main struct Tests {
    @MainActor static func main() {
        let manager = SchedulingManager.shared
        let first = BlockRule(name: "First")
        let second = BlockRule(name: "Second")
        DeviceActivityCenter.failNext = true
        precondition(!manager.applySchedule(for: first))
        precondition(manager.registrationErrors[first.id] != nil)
        precondition(manager.applySchedule(for: second))
        precondition(manager.registrationErrors[first.id] != nil, "Other success must not hide failure")
        precondition(manager.applySchedule(for: first))
        precondition(manager.registrationErrors[first.id] == nil)
        DeviceActivityCenter.failNext = true
        precondition(!manager.applySchedule(for: first))
        manager.removeSchedule(for: first)
        precondition(manager.registrationErrors[first.id] == nil)
        BlockStore.shared.blocks = [first, second]
        DeviceActivityCenter.registered = []
        manager.repairMissingSchedules()
        precondition(DeviceActivityCenter.registered.count == 2)
        let starts = DeviceActivityCenter.starts
        manager.repairMissingSchedules()
        precondition(DeviceActivityCenter.starts == starts, "Healthy schedules must not reset on foreground")
        print("10 schedule error/recovery checks passed against production manager with OS doubles")
    }
}
