import Foundation
import Combine
import DeviceActivity
import FamilyControls

/// Automatic recovery must never wait for Screen Time's synchronous XPC on the
/// main thread. Keep the entire transaction (including its recursive lease) on
/// one worker thread; only publish its result back on MainActor.
@MainActor
final class ForegroundRecovery: ObservableObject {
    static let shared = ForegroundRecovery()
    @Published private(set) var isChecking = true
    @Published private(set) var registeredUsageIDs: Set<UUID> = []
    private var started = false
    private var running = false
    private let queue = DispatchQueue(label: "name.amitsankaran.Block.foreground-recovery", qos: .userInitiated)

    private init() {}

    func start() {
        guard !started else { return }
        _ = ScreenTimeManager.shared
        started = true
        request()
    }

    /// Coalesce view appearance, authorization and periodic refresh triggers.
    /// There is no second worker, timeout retry, or main-thread wait on the lease.
    func request() {
        guard started, !running else { return }
        guard ScreenTimeManager.shared.authorizationStatus == .approved else {
            isChecking = false
            return
        }
        BlockStore.shared.flush()
        AppGroupStore.shared.flush()
        running = true
        isChecking = true
        queue.async {
            let result = Self.reconcile()
            Task { @MainActor in
                self.registeredUsageIDs = result.usageIDs
                SchedulingManager.shared.publishRecovery(errors: result.scheduleErrors)
                UsageLimitManager.shared.refresh()
                AdHocManager.shared.publishPersistedState()
                BreakManager.shared.publishPersistedState()
                self.running = false
                self.isChecking = false
            }
        }
    }

    private struct Result {
        var usageIDs: Set<UUID> = []
        var scheduleErrors: [UUID: String] = [:]
    }

    nonisolated private static func reconcile() -> Result {
        precondition(!Thread.isMainThread)
        var result = Result()
        guard let lease = EnforcementTransaction.begin() else { return result }
        defer { lease.finish() }
        // Load under the cross-process lease, not from a captured UI snapshot.
        let blocks = BlockResolution.loadBlocks()
        let groups = BlockResolution.loadGroups()
        let center = DeviceActivityCenter()
        let defaults = SharedDefaults.suite
        for block in blocks {
            if block.type == .schedule, let schedule = block.schedule {
                let name = DeviceActivityName(rawValue: "block.\(block.id.uuidString)")
                if !center.activities.contains(name) {
                    center.stopMonitoring([
                        DeviceActivityName(rawValue: "block.\(block.id.uuidString).early"),
                        DeviceActivityName(rawValue: "block.\(block.id.uuidString).late")
                    ])
                    do { try center.startMonitoring(name, during: schedule.deviceActivitySchedule()) }
                    catch { result.scheduleErrors[block.id] = "Couldn’t start this schedule. \(error.localizedDescription)" }
                }
                ScheduleEnforcement.reconcile(block: block)
            }
            if block.type == .timer {
                if defaults.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) is Date {
                    UsageMonitoring.reconcileLockout(blockID: block.id)
                } else if UsageMonitoring.usageEvent(for: block, groups: groups) == nil {
                    if UsageMonitoring.isUsageMonitorActive(for: block.id) { UsageMonitoring.stopUsageMonitor(for: block.id) }
                    defaults.set("No measurable apps selected. Open Lists and select apps, categories or websites in the Screen Time picker. Typed website addresses alone cannot measure usage.", forKey: SharedDefaults.Keys.usageError(blockID: block.id))
                } else if !UsageMonitoring.isUsageMonitorActive(for: block.id)
                            || defaults.string(forKey: SharedDefaults.Keys.usageError(blockID: block.id)) != nil {
                    UsageMonitoring.startUsageMonitor(for: block, groups: groups)
                }
                if UsageMonitoring.isUsageMonitorActive(for: block.id) { result.usageIDs.insert(block.id) }
            }
            if BreakMonitoring.breakEnd(blockID: block.id) != nil {
                BreakMonitoring.finishIfExpired(blockID: block.id)
            }
            if block.isEnabled && !BreakMonitoring.isOnBreak(blockID: block.id) {
                BlockingActuator.apply(tokens: BlockResolution.tokens(for: block, groups: groups), blockID: block.id)
            }
        }
        AdHocMonitoring.reconcile()
        return result
    }
}
