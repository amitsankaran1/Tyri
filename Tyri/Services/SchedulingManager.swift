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
    @Published var lastError: String?

    private let center = DeviceActivityCenter()
    private var refreshTimer: Timer?

    private init() {
        refresh()
        startPeriodicRefresh()
    }

    // MARK: - Activity name helpers

    static func activityName(for blockID: UUID, segment: BlockingSchedule.CrossingSegment = .full) -> DeviceActivityName {
        switch segment {
        case .full:  return DeviceActivityName(rawValue: "block.\(blockID.uuidString)")
        case .early: return DeviceActivityName(rawValue: "block.\(blockID.uuidString).early")
        case .late:  return DeviceActivityName(rawValue: "block.\(blockID.uuidString).late")
        }
    }

    // MARK: - Public API

    /// Register or update monitoring for a block's schedule.
    /// No-op (after teardown) when the block isn't a `.schedule` type or has no schedule.
    func applySchedule(for block: BlockRule) {
        // Always stop any prior monitoring first to avoid stacking.
        removeSchedule(for: block)

        guard block.type == .schedule, let schedule = block.schedule else { return }

        do {
            if schedule.crossesMidnight {
                try center.startMonitoring(
                    Self.activityName(for: block.id, segment: .early),
                    during: schedule.deviceActivitySchedule(crossingSegment: .early)
                )
                try center.startMonitoring(
                    Self.activityName(for: block.id, segment: .late),
                    during: schedule.deviceActivitySchedule(crossingSegment: .late)
                )
            } else {
                try center.startMonitoring(
                    Self.activityName(for: block.id, segment: .full),
                    during: schedule.deviceActivitySchedule(crossingSegment: .full)
                )
            }
            lastError = nil
            #if DEBUG
            DebugLog.shared.log(.deviceActivity, "applySchedule(\(block.name)): \(schedule.summary)")
            #endif
        } catch {
            print("❌ startMonitoring failed for block \(block.id): \(error)")
            lastError = "Couldn't start schedule: \(error.localizedDescription)"
            #if DEBUG
            DebugLog.shared.log(.deviceActivity, "applySchedule(\(block.name)) FAILED: \(error.localizedDescription)")
            #endif
        }
    }

    func removeSchedule(for block: BlockRule) {
        let names = [
            Self.activityName(for: block.id, segment: .full),
            Self.activityName(for: block.id, segment: .early),
            Self.activityName(for: block.id, segment: .late)
        ]
        center.stopMonitoring(names)
        // Also clear the running flag — if the schedule is removed mid-window,
        // the extension won't fire intervalDidEnd, so we must clean up.
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.running(blockID: block.id))
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

    /// Refresh `activeScheduledBlockIDs` from the App Group running flags.
    func refresh() {
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
