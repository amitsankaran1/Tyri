import Foundation

protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
@MainActor struct UIBackgroundTaskIdentifier: Hashable {
    let rawValue: Int
    static let invalid = Self(rawValue: -1)
}
@MainActor final class UIApplication {
    enum State { case active }
    static let shared = UIApplication()
    var applicationState = State.active
    var next = 0
    var assertions: [UIBackgroundTaskIdentifier: () -> Void] = [:]
    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        next += 1
        let id = UIBackgroundTaskIdentifier(rawValue: next)
        assertions[id] = expirationHandler
        return id
    }
    func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) { precondition(assertions.removeValue(forKey: id) != nil, "Duplicate assertion end") }
    func expire() { for handler in Array(assertions.values) { handler() } }
}
enum Probe {
    static let mutex = NSLock()
    static var outsideSchedule = false
    private static var leases = 0
    static func didBeginLease() { mutex.lock(); leases += 1; mutex.unlock() }
    static var leaseCount: Int { mutex.lock(); defer { mutex.unlock() }; return leases }
    static let release = DispatchSemaphore(value: 0)
    static let releaseObservation = DispatchSemaphore(value: 0)
    private static var entered = false
    private static var prefix = ""
    private static var shouldFail = false
    private static var observationCount = 0
    private static var pauseOnObservation: Int?
    private static var pausedObservation = false
    static var didEnter: Bool { mutex.lock(); defer { mutex.unlock() }; return entered }
    static var didPauseObservation: Bool { mutex.lock(); defer { mutex.unlock() }; return pausedObservation }
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
    static func pauseObservation(_ number: Int) {
        mutex.lock()
        observationCount = 0
        pauseOnObservation = number
        pausedObservation = false
        mutex.unlock()
    }
    static func afterObserve(_ names: Set<String>) -> Set<String> {
        mutex.lock()
        observationCount += 1
        let pause = observationCount == pauseOnObservation
        if pause { pausedObservation = true; pauseOnObservation = nil }
        mutex.unlock()
        if pause {
            precondition(!Thread.isMainThread, "Native observation must run off main")
            precondition(releaseObservation.wait(timeout: .now() + 10) == .success)
        }
        return names
    }
}
extension SharedDefaults.Keys { static let migratedToBlocksV2 = "migration" }
extension BlockResolution { static func loadBlocks() -> [BlockRule]? { Array(blocks.values) } }
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
    var loadError: String? = nil
    func flush() {}
    func reload() {}
}
@MainActor final class AppGroupStore {
    static let shared = AppGroupStore()
    var loadError: String? = nil
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
    var foregroundActive = true
    func setForegroundActive(_ active: Bool) { foregroundActive = active }
    func publishRecovery(errors: [UUID: String]) {}
}
@MainActor final class UsageLimitManager { static let shared = UsageLimitManager(); func refresh() {}
    func setForegroundActive(_ active: Bool) {} }
@MainActor final class AdHocManager { static let shared = AdHocManager(); func publishPersistedState() {} }
@MainActor final class BreakManager {
    static let shared = BreakManager()
    var lastError: String?
    func setForegroundActive(_ active: Bool) {}
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
        let queued = UUID()
        BlockResolution.blocks[queued] = BlockRule(id: queued, usageLimitMinutes: 15)
        recovery.request()
        try await wait { !recovery.isChecking }
        let initialUsage = UsageMonitoring.usageActivityName(for: queued)
        precondition(DeviceActivityCenter.events[initialUsage]?[UsageMonitoring.usageEventName]?.threshold.minute == 15)
        // The second observation is the pass's final observation: its plan has
        // already determined that no registration work remains. An edit now
        // needs the queued request to trigger a new pass after this one exits.
        Probe.pauseObservation(2)
        recovery.request()
        try await wait { Probe.didPauseObservation }
        BlockResolution.blocks[queued]!.usageLimitMinutes = 10
        recovery.request()
        Probe.releaseObservation.signal()
        try await wait {
            let usage = UsageMonitoring.usageActivityName(for: queued)
            return !recovery.isChecking
                && DeviceActivityCenter.events[usage]?[UsageMonitoring.usageEventName]?.threshold.minute == 10
        }
        // A Save accepted while the final observation is stalled must finish
        // without requiring another activation, even if Home follows immediately.
        Probe.pauseObservation(2)
        recovery.request()
        try await wait { Probe.didPauseObservation }
        BlockResolution.blocks[queued]!.usageLimitMinutes = 8
        recovery.requestAccepted()
        recovery.setActive(false)
        Probe.releaseObservation.signal()
        try await wait {
            let usage = UsageMonitoring.usageActivityName(for: queued)
            return !recovery.isChecking
                && DeviceActivityCenter.events[usage]?[UsageMonitoring.usageEventName]?.threshold.minute == 8
        }
        precondition(UsageProgress.reported(blockID: queued) == nil,
                     "Native registration fabricated an iOS usage report")
        try await wait { UIApplication.shared.assertions.isEmpty }
        recovery.setActive(true)
        try await wait { !recovery.isChecking }
        let retained = UsageMonitoring.usageActivityName(for: queued)
        precondition(recovery.hasChecked && recovery.registeredUsageIDs.contains(queued))
        recovery.requestAccepted()
        precondition(recovery.registeredUsageIDs.contains(queued), "Unrelated Save discarded a healthy presentation")
        recovery.request()
        try await wait { !recovery.isChecking }
        precondition(UsageMonitoring.usageActivityName(for: queued) == retained,
                     "Relaunch recovery reset a healthy allowance")
        recovery.setActive(false)
        BlockResolution.blocks[queued]!.usageLimitMinutes = 7
        recovery.requestAccepted()
        try await wait {
            DeviceActivityCenter.events[UsageMonitoring.usageActivityName(for: queued)]?[UsageMonitoring.usageEventName]?.threshold.minute == 7 && !recovery.isChecking
        }
        recovery.setActive(true)
        try await wait { !recovery.isChecking }
        print("PASS: Save retains healthy presentation and finishes even when accepted while inactive")
        print("PASS: accepted Save completes after Home; no synthetic progress; healthy owner retained")
        for expires in [false, true] {
            let breakID = UUID()
            BlockResolution.blocks[breakID] = BlockRule(id: breakID, type: .tag, isEnabled: true)
            State.shields.insert(breakID)
            Probe.prepare("break.\(breakID.uuidString)")
            let command = Task { try await recovery.command {
                BreakMonitoring.startBreak(blockID: breakID, minutes: 5)
            } }
            try await wait { Probe.didEnter }
            precondition(State.shields.contains(breakID), "Break lifted before its automatic end registered")
            let probeLease = EnforcementTransaction.begin(wait: false)
            precondition(probeLease != nil, "Break registration retained shared lease")
            probeLease?.finish()
            recovery.setActive(false)
            if expires { UIApplication.shared.expire() }
            let leases = Probe.leaseCount
            Probe.release.signal()
            let completed = (try? await command.value) ?? false
            if expires {
                precondition(!completed && Probe.leaseCount == leases,
                             "Expired command admitted a late state commit")
                precondition(State.shields.contains(breakID), "Expired break lifted protection")
            } else {
                precondition(completed && BreakMonitoring.isOnBreak(blockID: breakID),
                             "Accepted break did not finish after background")
            }
            recovery.setActive(true)
            try await wait { !recovery.isChecking }
            precondition(BreakMonitoring.isOnBreak(blockID: breakID),
                         "Interrupted successful registration did not reconcile its pending command")
            BreakMonitoring.endBreak(blockID: breakID, reapply: true)
        }
        print("PASS: break commands stay responsive, finish after Home, reject expired completion and recover pending identity")
        let earlyBreak = UUID()
        BlockResolution.blocks[earlyBreak] = BlockRule(id: earlyBreak, type: .tag, isEnabled: true)
        State.shields.insert(earlyBreak)
        Probe.prepare("break.\(earlyBreak)")
        let earlyCommand = Task { try await recovery.command {
            BreakMonitoring.startBreak(blockID: earlyBreak, minutes: 5)
        } }
        try await wait { Probe.didEnter }
        let pendingBreak = MonitorRegistration.pending("break.\(earlyBreak)")!
        TyriMonitorExtension().intervalDidStart(for: DeviceActivityName(rawValue: pendingBreak.name))
        precondition(BreakMonitoring.isOnBreak(blockID: earlyBreak) && !State.shields.contains(earlyBreak),
                     "Early native callback did not publish the accepted break")
        Probe.release.signal()
        let earlySucceeded = try await earlyCommand.value
        precondition(earlySucceeded)
        try await wait { !recovery.isChecking }
        BreakMonitoring.endBreak(blockID: earlyBreak, reapply: true)
        Probe.prepare("adhoc.")
        let temporary = Task { try await recovery.command {
            try AdHocMonitoring.start(group: AppGroup(), minutes: 30)
        } }
        try await wait { Probe.didEnter }
        let session = AdHocMonitoring.session!
        let pendingSession = MonitorRegistration.pending("adhoc.\(session.id)")!
        TyriMonitorExtension().intervalDidStart(for: DeviceActivityName(rawValue: pendingSession.name))
        precondition(AdHocMonitoring.session?.registered == true && State.shields.contains(session.id),
                     "Early native callback left temporary state and protection inconsistent")
        Probe.release.signal()
        try await temporary.value
        try await wait { !recovery.isChecking }
        AdHocMonitoring.finish(id: session.id)
        print("PASS: early break/temporary callbacks publish state while native return remains stalled")
        // No worker is available to perform cleanup after this command.
        // Completing the final command while inactive must close admission itself.
        BlockStore.shared.loadError = "Unreadable fixture"
        let gateID = UUID()
        BlockResolution.blocks[gateID] = BlockRule(id: gateID, type: .tag, isEnabled: true)
        Probe.prepare("break.\(gateID)")
        let gateCommand = Task { try await recovery.command {
            BreakMonitoring.startBreak(blockID: gateID, minutes: 5)
        } }
        try await wait { Probe.didEnter }
        recovery.setActive(false)
        Probe.release.signal()
        _ = try await gateCommand.value
        precondition(!EnforcementTransaction.effectsAreEnabled,
                     "Final background command left effect admission enabled without a recovery worker")
        BlockStore.shared.loadError = nil
        recovery.setActive(true)
        try await wait { !recovery.isChecking }
        BreakMonitoring.endBreak(blockID: gateID, reapply: true)
        let abandoned = UUID()
        BlockResolution.blocks[abandoned] = BlockRule(id: abandoned, type: .tag, isEnabled: true)
        SharedDefaults.suite.set(QAClock.now.addingTimeInterval(-1), forKey: "breakPendingEnd.\(abandoned)")
        recovery.request()
        try await wait { !recovery.isChecking }
        precondition(BreakMonitoring.pendingEnd(blockID: abandoned) == nil,
                     "Expired pending break permanently prevented another request")
        print("PASS: inactive command closes its own effect gate; expired pending breaks are retired")
        let orphan = UUID()
        BlockResolution.blocks[orphan] = BlockRule(id: orphan, type: .tag)
        State.shields.insert(orphan)
        recovery.request()
        try await wait { !recovery.isChecking }
        precondition(!State.shields.contains(orphan), "Inactive tag retained an old schedule shield")
        BlockResolution.blocks[orphan]!.type = .timer
        State.shields.insert(orphan)
        recovery.request()
        try await wait { !recovery.isChecking }
        precondition(!State.shields.contains(orphan), "Inactive usage allowance retained a stale shield")
        print("PASS: authoritative desired state clears stale shields after schedule-to-tag/timer transitions")
        let scheduleID = UUID()
        BlockResolution.blocks[scheduleID] = BlockRule(id: scheduleID, type: .schedule, schedule: BlockingSchedule())
        recovery.setActive(false)
        BlockingActuator.pending = scheduleID
        Probe.outsideSchedule = true
        Probe.pauseObservation(1)
        recovery.setActive(true)
        try await wait { Probe.didPauseObservation }
        precondition(!State.shields.contains(scheduleID), "Resume replayed an old schedule apply outside its window before observation")
        Probe.releaseObservation.signal()
        try await wait { !recovery.isChecking }
        Probe.outsideSchedule = false
        BlockResolution.blocks.removeValue(forKey: scheduleID)
        print("PASS: resumed schedule state is recomputed before pending replay and stalled observation")
        // Suspend while a native observation is stalled and a rerun is queued.
        Probe.pauseObservation(1)
        recovery.request()
        try await wait { Probe.didPauseObservation }
        recovery.request()
        precondition(!UIApplication.shared.assertions.isEmpty, "Pass has no suspension assertion during native observation")
        UIApplication.shared.expire()
        let starts = DeviceActivityCenter.starts
        let leases = Probe.leaseCount
        precondition(!SchedulingManager.shared.foregroundActive)
        recovery.request()
        Probe.releaseObservation.signal()
        for _ in 0..<20 { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(Probe.leaseCount == leases, "Expiration admitted a new lease")
        precondition(DeviceActivityCenter.starts == starts && !recovery.isChecking,
                     "Backgrounded recovery performed a registration or queued rerun")
        recovery.setActive(true)
        try await wait { !recovery.isChecking }
        precondition(SchedulingManager.shared.foregroundActive)
        for _ in 0..<10 { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(UIApplication.shared.assertions.isEmpty, "Background assertion leaked after completion/expiration")
        print("PASS: background assertion expires, stops recovery and ends exactly once")
        print("PASS: background cancels pending recovery/rerun and activation resumes")
        print("PASS: request during final observation queues a fresh usage-limit registration")
        print("PASS: break expiry re-shields BEFORE stalled IPC returns and retains its used allowance")
        print("PASS: migration retries after lease contention exactly once without blocking MainActor")
    }
}
