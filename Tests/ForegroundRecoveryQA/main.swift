import Foundation

protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct DeviceActivityName: Hashable { var rawValue: String }
struct Schedule { func deviceActivitySchedule() -> Int { 0 } }
struct BlockRule {
    enum Kind { case schedule, timer, tag }
    let id = UUID()
    var type: Kind = .timer
    var schedule: Schedule? = nil
    var isEnabled = false
}
enum Probe {
    static let lock = NSLock()
    static let release = DispatchSemaphore(value: 0)
    private static var entered = false
    static var didEnter: Bool { lock.lock(); defer { lock.unlock() }; return entered }
    static func waitForIPC() {
        precondition(!Thread.isMainThread, "DeviceActivity must not run on main")
        lock.lock(); entered = true; lock.unlock()
        precondition(release.wait(timeout: .now() + 10) == .success)
    }
}
struct DeviceActivityCenter {
    var activities: [DeviceActivityName] { [] }
    func startMonitoring(_ name: DeviceActivityName, during schedule: Int) throws {}
    func stopMonitoring(_ names: [DeviceActivityName]) {}
}
enum SharedDefaults {
    static let suite = UserDefaults(suiteName: "tyri-recovery-\(UUID())")!
    enum Keys {
        static func usageLockEnd(blockID: UUID) -> String { "lock.\(blockID)" }
        static func usageError(blockID: UUID) -> String { "error.\(blockID)" }
    }
}
enum EnforcementTransaction {
    static let lock = NSRecursiveLock()
    final class Lease { func finish() { lock.unlock() } }
    static func begin() -> Lease? { precondition(!Thread.isMainThread); lock.lock(); return Lease() }
}
enum BlockResolution {
    static let block = BlockRule()
    static func loadBlocks() -> [BlockRule] { [block] }
    static func loadGroups() -> [Int] { [] }
    static func tokens(for block: BlockRule, groups: [Int]) -> Int { 0 }
}
enum UsageMonitoring {
    static func reconcileLockout(blockID: UUID) {}
    static func usageEvent(for block: BlockRule, groups: [Int]) -> Int? { 1 }
    static func isUsageMonitorActive(for id: UUID) -> Bool { Probe.waitForIPC(); return true }
    static func stopUsageMonitor(for id: UUID) {}
    static func startUsageMonitor(for block: BlockRule, groups: [Int]) {}
}
enum ScheduleEnforcement { static func reconcile(block: BlockRule) {} }
enum BreakMonitoring {
    static func breakEnd(blockID: UUID) -> Date? { nil }
    static func finishIfExpired(blockID: UUID) {}
    static func isOnBreak(blockID: UUID) -> Bool { false }
}
enum BlockingActuator { static func apply(tokens: Int, blockID: UUID) {} }
enum AdHocMonitoring { static func reconcile() {} }
@MainActor final class ScreenTimeManager {
    enum Authorization { case approved }
    static let shared = ScreenTimeManager()
    var authorizationStatus: Authorization = .approved
}
@MainActor final class BlockStore {
    static let shared = BlockStore()
    var flushes = 0
    func flush() { flushes += 1 }
}
@MainActor final class AppGroupStore { static let shared = AppGroupStore(); func flush() {} }
@MainActor final class SchedulingManager {
    static let shared = SchedulingManager()
    var publications = 0
    func publishRecovery(errors: [UUID: String]) { publications += 1 }
}
@MainActor final class UsageLimitManager { static let shared = UsageLimitManager(); func refresh() {} }
@MainActor final class AdHocManager { static let shared = AdHocManager(); func publishPersistedState() {} }
@MainActor final class BreakManager { static let shared = BreakManager(); func publishPersistedState() {} }

@main struct Tests {
    @MainActor static func main() async throws {
        let recovery = ForegroundRecovery.shared
        recovery.request() // View construction before startup must not run IPC.
        precondition(BlockStore.shared.flushes == 0)
        recovery.start()
        for _ in 0..<100 where !Probe.didEnter { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(Probe.didEnter, "The worker must exercise the stalled monitoring call")
        precondition(recovery.isChecking, "Unconfirmed monitoring must remain visibly pending")
        // This MainActor heartbeat runs while synchronous monitoring is stalled.
        var heartbeat = 0
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 10_000_000)
            heartbeat += 1
            recovery.request()
        }
        precondition(heartbeat == 5 && BlockStore.shared.flushes == 1, "Refreshes must coalesce without blocking MainActor")
        precondition(SchedulingManager.shared.publications == 0, "Do not publish success before IPC returns")
        // There are two registration reads in this timer path.
        Probe.release.signal(); Probe.release.signal()
        for _ in 0..<100 where recovery.isChecking { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(!recovery.isChecking)
        precondition(recovery.registeredUsageIDs == [BlockResolution.block.id])
        precondition(SchedulingManager.shared.publications == 1)
        print("PASS: production recovery keeps MainActor responsive during stalled IPC, coalesces triggers, and publishes only after completion")
    }
}
