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

    private let center = DeviceActivityCenter()
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
        guard let transition = EnforcementTransaction.begin() else { return false }
        defer { transition.finish() }

        defer { ScheduleEnforcement.reconcile(block: block) }
        // Remove old split monitors without clearing this window's state/break.
        center.stopMonitoring([
            Self.activityName(for: block.id, segment: .early),
            Self.activityName(for: block.id, segment: .late)
        ])

        guard block.type == .schedule, let schedule = block.schedule else {
            removeSchedule(for: block)
            return true
        }

        let base = "block.\(block.id.uuidString)"
        let context = ScheduleEnforcement.registrationContext(schedule)
        guard let ticket = MonitorRegistration.reserve(base, legacyName: base, context: context) else { return false }
        let obsolete = MonitorRegistration.retirementNames(observed: Set(center.activities.map(\.rawValue)))
        if !obsolete.isEmpty {
            center.stopMonitoring(obsolete.map { DeviceActivityName(rawValue: $0) })
            MonitorRegistration.acknowledgeRetired(obsolete)
        }
        if center.activities.count >= 20 {
            // A replacement needs a slot too. Retire only this schedule's
            // previous owner, matching the existing replacement-at-capacity rule.
            let previous = Self.activityName(for: block.id)
            center.stopMonitoring([previous])
        }
        do {
            try center.startMonitoring(DeviceActivityName(rawValue: ticket.name),
                                       during: schedule.deviceActivitySchedule())
            _ = MonitorRegistration.finish(ticket, context: context, succeeded: true)
            let retired = MonitorRegistration.retirementNames(observed: Set(center.activities.map(\.rawValue)))
            center.stopMonitoring(retired.map { DeviceActivityName(rawValue: $0) })
            MonitorRegistration.acknowledgeRetired(retired)
            registrationErrors.removeValue(forKey: block.id)
            #if DEBUG
            DebugLog.shared.log(.deviceActivity, "applySchedule(\(block.name)): \(schedule.summary)")
            #endif
            return true
        } catch {
            _ = MonitorRegistration.finish(ticket, context: context, succeeded: false)
            print("❌ startMonitoring failed for block \(block.id): \(error)")
            registrationErrors[block.id] = "Couldn’t start this schedule. \(error.localizedDescription)"
            #if DEBUG
            DebugLog.shared.log(.deviceActivity, "applySchedule(\(block.name)) FAILED: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func removeSchedule(for block: BlockRule) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        registrationErrors.removeValue(forKey: block.id)
        let names = [
            Self.activityName(for: block.id, segment: .full),
            Self.activityName(for: block.id, segment: .early),
            Self.activityName(for: block.id, segment: .late)
        ]
        MonitorRegistration.invalidate("block.\(block.id.uuidString)", legacyName: "block.\(block.id.uuidString)")
        center.stopMonitoring(names)
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
        for block in BlockStore.shared.blocks where block.type == .schedule && block.schedule != nil {
            if !center.activities.contains(Self.activityName(for: block.id)) || registrationErrors[block.id] != nil {
                applySchedule(for: block)
            }
        }
        refresh()
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

    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
}
