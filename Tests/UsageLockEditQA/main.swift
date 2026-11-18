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
    func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) { precondition(assertions.removeValue(forKey: id) != nil) }
}
enum Probe {
    static var outsideSchedule = false
    static func didBeginLease() {}
    static func afterStart(_ name: DeviceActivityName) throws {}
    static func afterObserve(_ names: Set<String>) -> Set<String> { names }
}
extension SharedDefaults.Keys { static let migratedToBlocksV2 = "migration" }
extension BlockResolution {
    static func loadBlocks() -> [BlockRule]? { Array(blocks.values) }
}
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
    var loadError: String?
    func flush() {}
    func reload() {}
}
@MainActor final class AppGroupStore {
    static let shared = AppGroupStore()
    var loadError: String?
    func flush() {}
    func reload() {}
}
@MainActor enum Migration { static func runIfNeeded() {} }
@MainActor final class SchedulingManager {
    static let shared = SchedulingManager()
    func setForegroundActive(_ active: Bool) {}
    func publishRecovery(errors: [UUID: String]) {}
}
@MainActor final class UsageLimitManager {
    static let shared = UsageLimitManager()
    func refresh() {}
    func setForegroundActive(_ active: Bool) {}
}
@MainActor final class AdHocManager { static let shared = AdHocManager(); func publishPersistedState() {} }
@MainActor final class BreakManager {
    static let shared = BreakManager()
    var lastError: String?
    func setForegroundActive(_ active: Bool) {}
    func publishPersistedState() {}
}

@main struct Tests {
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Timed out waiting for usage recovery")
    }

    /// Save persists the edited rule, then asks foreground recovery to reconcile
    /// monitors. Recovery keeps an observed allowance when its semantic inputs
    /// are unchanged. Lock duration is applied later, when the threshold fires.
    @MainActor static func main() async throws {
        SharedDefaults.suite.set(true, forKey: SharedDefaults.Keys.migratedToBlocksV2)
        let id = UUID()
        BlockResolution.blocks[id] = BlockRule(id: id, usageLockMinutes: 180, usageLimitMinutes: 10)
        let recovery = ForegroundRecovery.shared
        recovery.start()
        try await wait {
            !recovery.isChecking && DeviceActivityCenter.schedules[UsageMonitoring.usageActivityName(for: id)] != nil
        }

        let allowance = UsageMonitoring.usageActivityName(for: id)
        let originalEvent = DeviceActivityCenter.events[allowance]?[UsageMonitoring.usageEventName]
        precondition(originalEvent?.threshold.minute == 10, "Fixture did not register a 10 minute allowance")
        precondition(originalEvent?.includesPastActivity == false, "Running allowance must be the counter that excludes activity from before it started")
        TyriMonitorExtension().eventDidReachThreshold(DeviceActivityEvent.Name("progress.6"), activity: allowance)
        precondition(UsageProgress.reported(blockID: id) == 6, "iOS progress report did not stick to today's allowance")
        let generation = SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: id))
        precondition(generation?.isEmpty == false)
        let context = UsageMonitoring.registrationContext(for: BlockResolution.blocks[id]!, groups: [])

        var lockEdit = BlockResolution.blocks[id]!
        lockEdit.usageLockMinutes = 120
        precondition(UsageMonitoring.registrationContext(for: lockEdit, groups: []) == context,
                     "Lock duration is a monitoring input, so saving it would mint a new allowance")
        var allowanceEdit = lockEdit
        allowanceEdit.usageLimitMinutes = 20
        precondition(UsageMonitoring.registrationContext(for: allowanceEdit, groups: []) != context,
                     "Allowance edits must stay distinct from lock-duration edits")

        let starts = DeviceActivityCenter.starts
        let stopAllCalls = DeviceActivityCenter.stopAllCalls
        let activities = Set(DeviceActivityCenter().activities)
        SharedDefaults.suite.removeObject(forKey: EnforcementDiagnostics.key("usageObservation", id))
        SharedDefaults.suite.removeObject(forKey: EnforcementDiagnostics.key("usageReplacement", id))
        BlockResolution.blocks[id]!.usageLockMinutes = 120
        recovery.requestAccepted()
        // The pass can finish inside the first wait slice, so completion is the
        // rewritten preservation receipt rather than a transient isChecking edge.
        try await wait {
            !recovery.isChecking &&
                (SharedDefaults.suite.string(forKey: EnforcementDiagnostics.key("usageObservation", id)) ?? "")
                    .contains("Preserved observed allowance")
        }

        let preserved = UsageMonitoring.usageActivityName(for: id)
        precondition(preserved == allowance, "Lock-duration edit replaced the allowance identity")
        precondition(DeviceActivityCenter.starts == starts, "Lock-duration edit started a new DeviceActivity monitor")
        precondition(DeviceActivityCenter.stopAllCalls == stopAllCalls, "Lock-duration edit stopped every activity")
        precondition(Set(DeviceActivityCenter().activities) == activities, "Lock-duration edit stopped or added a monitor")
        let event = DeviceActivityCenter.events[preserved]?[UsageMonitoring.usageEventName]
        precondition(event?.threshold.minute == 10 && event?.includesPastActivity == false,
                     "Lock-duration edit replaced the running threshold event")
        precondition(SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: id)) == generation,
                     "Lock-duration edit published a new usage generation")
        precondition(UsageProgress.reported(blockID: id) == 6, "Lock-duration edit cleared usage already counted today")
        let observation = SharedDefaults.suite.string(forKey: EnforcementDiagnostics.key("usageObservation", id)) ?? ""
        precondition(observation.contains("Preserved observed allowance") && observation.contains(allowance.rawValue),
                     "Recovery did not record that the observed allowance was kept: \(observation)")
        precondition(SharedDefaults.suite.string(forKey: EnforcementDiagnostics.key("usageReplacement", id)) == nil,
                     "Recovery reserved a replacement allowance for a lock-duration edit")
        precondition(recovery.registeredUsageIDs.contains(id), "A preserved allowance disappeared from the registered set")

        TyriMonitorExtension().eventDidReachThreshold(UsageMonitoring.usageEventName, activity: preserved)
        let end = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date
        let gap = end?.timeIntervalSince(QAClock.now) ?? -1
        precondition(gap > 119 * 60 && gap <= 120 * 60,
                     "The next lock did not use the edited 2 hour duration (gap \(gap))")
        print("PASS: editing only the lock duration keeps today's allowance, counted usage, and activity identity")
        print("PASS: the next threshold locks for the edited duration")
    }
}
