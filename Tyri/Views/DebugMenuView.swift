//
//  DebugMenuView.swift
//  Tyri
//
//  Test affordances for simulator development. Compiled out of release.
//

#if DEBUG

import SwiftUI
import Combine
import FamilyControls

struct DebugMenuView: View {
    @StateObject private var blockStore = BlockStore.shared
    @StateObject private var schedulingManager = SchedulingManager.shared
    @StateObject private var configStore = AppConfigurationStore.shared
    @StateObject private var screenTimeManager = ScreenTimeManager.shared
    @StateObject private var cooldownManager = CooldownManager.shared
    @StateObject private var debugLog = DebugLog.shared

    @State private var refreshTick = 0
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var snapshot: DebugSimulator.GlobalSnapshot {
        // refreshTick is read so SwiftUI re-evaluates on the timer
        _ = refreshTick
        return DebugSimulator.snapshot()
    }

    var body: some View {
        List {
            globalStateSection
            tagFlowSection
            presetsSection
            logSection
            dangerZoneSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Debug Menu")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            refreshTick &+= 1
        }
    }

    // MARK: - Global state

    private var globalStateSection: some View {
        Section("Global State") {
            row("Screen Time auth", value: authString(snapshot.authorizationStatus))
            row("App lists", value: "\(snapshot.groupCount)")
            row("Blocks", value: "\(snapshot.blocks.count)")
            row("Active scheduled blocks", value: "\(snapshot.activeScheduledIDs.count)")
            if let id = snapshot.activeCooldownBlockID {
                row("Active cooldown",
                    value: shortID(id) + " (\(Int(cooldownManager.remaining))s)")
            }
        }
    }

    // MARK: - Tag flow

    private var tagFlowSection: some View {
        Section("NFC Tag Flow") {
            if let tag = snapshot.registeredTag {
                row("Registered tag", value: tag)
            } else {
                Text("No tag registered").foregroundStyle(.secondary)
            }

            Button("Simulate registered tag scan (toggle)") {
                DebugSimulator.simulateRegisteredTagScan()
            }
            .disabled(snapshot.registeredTag == nil)

            Button("Simulate unknown tag scan") {
                DebugSimulator.simulateUnknownTagScan()
            }

            Button("Register fake tag") {
                DebugSimulator.registerFakeTag()
            }
            .disabled(snapshot.registeredTag != nil)

            if snapshot.registeredTag != nil {
                Button("Clear tag registration", role: .destructive) {
                    configStore.clearTagRegistration()
                    DebugLog.shared.log(.nfc, "cleared tag registration")
                }
            }
        }
    }

    // MARK: - Blocks

    @ViewBuilder
    private var presetsSection: some View {
        if snapshot.blocks.isEmpty {
            Section("Blocks") {
                Text("No blocks — create one from the Blocks tab.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(snapshot.blocks) { block in
                Section("\(block.name) [\(block.type.rawValue)]") {
                    presetRows(block)
                }
            }
        }
    }

    @ViewBuilder
    private func presetRows(_ block: DebugSimulator.BlockSnapshot) -> some View {
        row("ID", value: shortID(block.id))
        row("Lists", value: block.groupNames.isEmpty ? "—" : block.groupNames.joined(separator: ", "))
        row("Apps / Categories", value: "\(block.appCount) / \(block.categoryCount)")
        if block.type == .schedule { row("Schedule", value: block.scheduleSummary ?? "—") }
        row("Manual enabled", value: block.isEnabled ? "ON" : "off")
        row("Scheduled running flag", value: block.isScheduledRunning ? "ON" : "off")
        row("Cooldown minutes", value: "\(block.cooldownMinutes)")
        if let endsAt = block.cooldownEndsAt {
            let secs = Int(endsAt.timeIntervalSinceNow)
            row("Cooldown ends in", value: secs > 0 ? "\(secs)s" : "expired")
        }
        if block.type != .timer {
            row("Break minutes", value: block.breakMinutes == 0 ? "off" : "\(block.breakMinutes)")
            row("Break used", value: block.breakUsed ? "YES" : "no")
        }
        if let endsAt = block.breakEndsAt {
            let secs = Int(endsAt.timeIntervalSinceNow)
            row("Break ends in", value: secs > 0 ? "\(secs)s" : "expired")
        }
        if block.type == .timer {
            row("Usage limit", value: block.usageLimitMinutes.map { "\($0) min → lock \(block.usageLockMinutes)m" } ?? "off")
        }
        if let endsAt = block.usageLockEndsAt {
            let secs = Int(endsAt.timeIntervalSinceNow)
            row("Usage lock ends in", value: secs > 0 ? "\(secs / 60)m \(secs % 60)s" : "expired")
        }

        if block.type == .schedule {
            Button("Fire interval start now") { DebugSimulator.fireScheduleStart(blockID: block.id) }
            Button("Fire interval end now") { DebugSimulator.fireScheduleEnd(blockID: block.id) }
        }
        Button("Start 10s cooldown") {
            DebugSimulator.startShortCooldown(blockID: block.id, seconds: 10)
        }
        if cooldownManager.activeCooldown?.blockID == block.id {
            Button("Fast-forward cooldown") {
                DebugSimulator.expireCooldown()
            }
        }
        if block.type == .timer && block.usageLimitMinutes != nil {
            Button("Fire usage threshold (lock now)") {
                DebugSimulator.fireUsageThreshold(blockID: block.id)
            }
        }
        if block.usageLockEndsAt != nil {
            Button("Expire usage lock") {
                DebugSimulator.expireUsageLock(blockID: block.id)
            }
        }
        if block.type != .timer && block.breakMinutes > 0 && block.breakEndsAt == nil {
            Button("Start break now") {
                DebugSimulator.startBreak(blockID: block.id)
            }
        }
        if block.breakEndsAt != nil {
            Button("Expire break now") {
                DebugSimulator.expireBreak(blockID: block.id)
            }
        }

        // Shield inspector: live readback of every store this block occupies.
        // "chunkN apps X, web Y · cats Z" should match the selection; a dropped
        // property (the silent >50-token failure) reads back as 0.
        VStack(alignment: .leading, spacing: 4) {
            Text("Shield store readback")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(BlockingActuator.audit(blockID: block.id))
                .font(.caption.monospaced())
            if let audit = block.shieldAudit {
                Text("Last apply: \(audit)")
                    .font(.caption.monospaced())
                    .foregroundStyle(audit.hasPrefix("MISMATCH") ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 2)
        Button("Re-apply shield WITHOUT categories store") {
            DebugSimulator.reapplyShield(blockID: block.id, includeCategories: false)
        }
        Button("Re-apply full shield") {
            DebugSimulator.reapplyShield(blockID: block.id, includeCategories: true)
        }
    }

    // MARK: - Log

    private var logSection: some View {
        Section {
            if debugLog.entries.isEmpty {
                Text("No events yet").foregroundStyle(.secondary)
            } else {
                ForEach(debugLog.entries.suffix(40).reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.channel.emoji)
                            Text(entry.channel.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption.monospaced())
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            HStack {
                Text("Event Log")
                Spacer()
                Button("Clear") { debugLog.clear() }
                    .font(.caption)
            }
        }
    }

    // MARK: - Danger zone

    private var dangerZoneSection: some View {
        Section("Danger Zone") {
            Button("Reset runtime state (keep presets)", role: .destructive) {
                DebugSimulator.resetAllRuntime()
            }
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func authString(_ status: AuthorizationStatus) -> String {
        String(describing: status)
    }
}

#endif
