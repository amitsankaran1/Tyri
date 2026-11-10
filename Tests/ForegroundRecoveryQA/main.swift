import Foundation

protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
enum Probe {
    static let mutex = NSLock()
    static let release = DispatchSemaphore(value: 0)
    private static var entered = false
    private static var prefix = ""
    private static var shouldFail = false
    static var didEnter: Bool { mutex.lock(); defer { mutex.unlock() }; return entered }
    static func prepare(_ value: String, fail: Bool = false) {
        mutex.lock(); entered = false; prefix = value; shouldFail = fail; mutex.unlock()
    }
    static func afterStart(_ name: DeviceActivityName) throws {
        mutex.lock()
        let matches = name.rawValue.hasPrefix(prefix) && !prefix.isEmpty
        let pause = matches && !entered
        if pause { entered = true }
        let fail = matches && shouldFail
        mutex.unlock()
        if pause {
            precondition(!Thread.isMainThread, "Automatic native registration must run off main")
            precondition(release.wait(timeout: .now() + 10) == .success)
        }
        if fail { throw NSError(domain: "late-registration-failure", code: 1) }
    }
}
extension SharedDefaults.Keys { static let migratedToBlocksV2 = "migration" }
extension BlockResolution { static func loadBlocks() -> [BlockRule] { Array(blocks.values) } }
extension BlockingSchedule {
    func deviceActivitySchedule() -> DeviceActivitySchedule {
        DeviceActivitySchedule(intervalStart: DateComponents(hour: 0), intervalEnd: DateComponents(hour: 23), repeats: true)
    }
}
@MainActor final class ScreenTimeManager {
    enum Authorization { case approved }
    static let shared = ScreenTimeManager()
    var authorizationStatus: Authorization = .approved
}
@MainActor final class BlockStore {
    static let shared = BlockStore()
    func flush() {}
    func reload() {}
}
@MainActor final class AppGroupStore {
    static let shared = AppGroupStore()
    func flush() {}
    func reload() {}
}
@MainActor enum Migration {
    static var runs = 0
    static func runIfNeeded() {
        guard !SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.migratedToBlocksV2) else { return }
        runs += 1
        SharedDefaults.suite.set(true, forKey: SharedDefaults.Keys.migratedToBlocksV2)
    }
}
@MainActor final class SchedulingManager {
    static let shared = SchedulingManager()
    func publishRecovery(errors: [UUID: String]) {}
}
@MainActor final class UsageLimitManager { static let shared = UsageLimitManager(); func refresh() {} }
@MainActor final class AdHocManager { static let shared = AdHocManager(); func publishPersistedState() {} }
@MainActor final class BreakManager {
    static let shared = BreakManager()
    var lastError: String?
    var publications = 0
    func publishPersistedState() { publications += 1 }
}

@main struct Tests {
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Timed out waiting for deterministic worker checkpoint")
    }
    @MainActor static func main() async throws {
        let recovery = ForegroundRecovery.shared
        recovery.request()
        precondition(!SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.migratedToBlocksV2))
        let held = DispatchSemaphore(value: 0), unlock = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let lease = EnforcementTransaction.begin()!
            held.signal(); unlock.wait(); lease.finish()
        }
        held.wait()
        for failure in [false, true] {
            let id = UUID()
            BlockResolution.blocks[id] = BlockRule(id: id)
            Probe.prepare("usage.\(id.uuidString)", fail: failure)
            if Migration.runs == 0 {
                recovery.start()
                for _ in 0..<5 { try await Task.sleep(nanoseconds: 10_000_000) }
                precondition(Migration.runs == 0, "Contended migration blocked or stole the lease")
                unlock.signal()
            } else { recovery.request() }
            try await wait { Probe.didEnter }
            precondition(BreakManager.shared.publications > 0, "Persisted break timer was not restored before native IPC")
            // Both the UI heartbeat and a callback's lease acquisition remain
            // available while native IPC is stalled in the recovery worker.
            for _ in 0..<5 { try await Task.sleep(nanoseconds: 10_000_000) }
            guard let lease = EnforcementTransaction.begin(wait: false) else {
                preconditionFailure("Stalled native IPC retained the enforcement lease")
            }
            let pending = MonitorRegistration.pending("usage.\(id.uuidString)")!
            lease.finish()
            let monitor = TyriMonitorExtension()
            monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: DeviceActivityName(rawValue: pending.name))
            let deadline = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as! Date
            precondition(State.shields.contains(id))
            let progress = UsageProgress.reported(blockID: id)
            Probe.release.signal()
            try await wait { !recovery.isChecking }
            precondition(SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date == deadline,
                         "Late registration completion changed a consumed allowance's fixed lock deadline")
            precondition(UsageProgress.reported(blockID: id) == progress, "Late commit reset callback progress")
            precondition(!DeviceActivityCenter().activities.contains(DeviceActivityName(rawValue: pending.name)),
                         "Late completion resurrected the consumed monitor")
            print("PASS: stalled IPC releases lease/MainActor; early threshold survives late \(failure ? "failure" : "success")")
        }
        let tag = UUID()
        BlockResolution.blocks[tag] = BlockRule(id: tag, type: .tag, isEnabled: true)
        let end = Date(timeIntervalSince1970: floor(QAClock.now.timeIntervalSince1970) + 5)
        SharedDefaults.suite.set(end, forKey: SharedDefaults.Keys.breakEnd(blockID: tag))
        SharedDefaults.suite.set(true, forKey: SharedDefaults.Keys.breakUsed(blockID: tag))
        Probe.prepare("break.\(tag.uuidString)")
        recovery.request()
        try await wait { Probe.didEnter }
        QAClock.now = end.addingTimeInterval(1)
        recovery.request()
        precondition(recovery.isChecking, "The native worker was not still stalled")
        precondition(BreakMonitoring.breakEnd(blockID: tag) == nil && State.shields.contains(tag),
                     "Deadline fallback waited for stalled IPC before restoring protection")
        precondition(BreakMonitoring.breakUsed(blockID: tag))
        Probe.release.signal()
        try await wait { !recovery.isChecking }
        precondition(BreakMonitoring.breakEnd(blockID: tag) == nil && State.shields.contains(tag),
                     "Deadline crossing during IPC failed to restore protection in the same cycle")
        precondition(BreakMonitoring.breakUsed(blockID: tag), "Recovery renewed the break allowance")
        precondition(Migration.runs == 1)
        print("PASS: break expiry re-shields BEFORE stalled IPC returns and retains its used allowance")
        print("PASS: migration retries after lease contention exactly once without blocking MainActor")
    }
}
