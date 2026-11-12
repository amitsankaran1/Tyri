//
//  SchedulingManager.swift
//  Tyri
//
//  Wraps `DeviceActivityCenter` to register/unregister scheduled monitoring per
//  `.schedule` block. The actual shield application happens in the TyriMonitor
//  extension's `intervalDidStart`/`intervalDidEnd` callbacks.
//

import Foundation
import DeviceActivity
import Combine

@MainActor
class SchedulingManager: ObservableObject {
    static let shared = SchedulingManager()

    @Published private(set) var activeScheduledBlockIDs: Set<UUID> = []
    @Published private(set) var registrationErrors: [UUID: String] = [:]

    private var refreshTimer: Timer?

    private init() {
        refresh()
        startPeriodicRefresh()
    }

    // MARK: - Activity name helpers

    static func activityName(for blockID: UUID, segment: BlockingSchedule.CrossingSegment = .full) -> DeviceActivityName {
        switch segment {
        case .full:
            let base = "block.\(blockID.uuidString)"
            return DeviceActivityName(rawValue: MonitorRegistration.current(base, legacyName: base))
        case .early: return DeviceActivityName(rawValue: "block.\(blockID.uuidString).early")
        case .late:  return DeviceActivityName(rawValue: "block.\(blockID.uuidString).late")
        }
    }

    // MARK: - Public API

    /// Register or update monitoring for a block's schedule.
    /// No-op (after teardown) when the block isn't a `.schedule` type or has no schedule.
    @discardableResult
    func applySchedule(for block: BlockRule) -> Bool {
        ForegroundRecovery.shared.requestAccepted()
        return true // accepted; current registration/error is published by recovery
    }

    func removeSchedule(for block: BlockRule) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { ForegroundRecovery.shared.finish(transition) }

        registrationErrors.removeValue(forKey: block.id)
        let names = [
            Self.activityName(for: block.id, segment: .full),
            Self.activityName(for: block.id, segment: .early),
            Self.activityName(for: block.id, segment: .late)
        ]
        MonitorRegistration.invalidate("block.\(block.id.uuidString)", legacyName: "block.\(block.id.uuidString)")
        EnforcementTransaction.afterUnlock(key: "removeSchedule.\(block.id)") {
            DeviceActivityCenter().stopMonitoring(names)
        }
        // Also clear the running flag — if the schedule is removed mid-window,
        // the extension won't fire intervalDidEnd, so we must clean up.
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.running(blockID: block.id))
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.scheduleWindowStart(blockID: block.id))
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.scheduleReleasedUntil(blockID: block.id))
        #if DEBUG
        DebugLog.shared.log(.deviceActivity, "removeSchedule(\(block.name))")
        #endif
    }

    /// Re-register all schedule blocks. Call once at launch — `startMonitoring` is
    /// idempotent for the same name + schedule.
    func reapplyAllSchedules() {
        for block in BlockStore.shared.blocks where block.type == .schedule && block.schedule != nil {
            applySchedule(for: block)
        }
        refresh()
    }

    /// Foreground repair preserves healthy registrations and their current windows.
    func repairMissingSchedules() {
        ForegroundRecovery.shared.request()
    }

    /// Repair missing/delayed callbacks before publishing current schedule state.
    func refresh() {
        publishRecovery(errors: registrationErrors)
        ForegroundRecovery.shared.request()
    }

    /// Publish persisted state only; view construction must not acquire a lease
    /// or contact DeviceActivity while the recovery worker owns that lease.
    func publishRecovery(errors: [UUID: String]) {
        if registrationErrors != errors { registrationErrors = errors }
        var ids: Set<UUID> = []
        let suite = SharedDefaults.suite
        for block in BlockStore.shared.blocks where block.type == .schedule {
            if suite.bool(forKey: SharedDefaults.Keys.running(blockID: block.id)) {
                ids.insert(block.id)
            }
        }
        if ids != activeScheduledBlockIDs {
            activeScheduledBlockIDs = ids
        }
    }

    func setForegroundActive(_ active: Bool) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if active { startPeriodicRefresh() }
    }

    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
}
