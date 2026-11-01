import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct DeviceActivityName: Hashable { var rawValue: String }
struct DeviceActivitySchedule {}
struct DeviceActivityCenter {
    static var failNext = false
    func startMonitoring(_ name: DeviceActivityName, during: DeviceActivitySchedule) throws {
        if Self.failNext { Self.failNext = false; throw NSError(domain: "QA", code: 1) }
    }
    func stopMonitoring(_ names: [DeviceActivityName]) {}
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
        print("8 schedule error checks passed against production manager with OS doubles")
    }
}
