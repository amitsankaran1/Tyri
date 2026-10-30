//
//  Migration.swift
//  Tyri
//
//  One-time migration from the old preset model (presets.v1, apps embedded in
//  each preset) to the new App Groups + Blocks model. Runs once on launch.
//

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
enum Migration {

    static func runIfNeeded() {
        let suite = SharedDefaults.suite
        guard !suite.bool(forKey: SharedDefaults.Keys.migratedToBlocksV2) else { return }

        var newGroups: [AppGroup] = []
        var newBlocks: [BlockRule] = []

        // 1. Legacy presets → one group per preset + a block per mechanic it used.
        if let data = suite.data(forKey: SharedDefaults.Keys.presets),
           let legacy = try? JSONDecoder().decode([LegacyPreset].self, from: data) {
            for p in legacy {
                let group = AppGroup(name: p.name, selection: p.selection)
                var groupAdded = false
                func groupID() -> UUID {
                    if !groupAdded { newGroups.append(group); groupAdded = true }
                    return group.id
                }
                if let schedule = p.schedule {
                    newBlocks.append(BlockRule(name: p.name, type: .schedule,
                                               appGroupIDs: [groupID()],
                                               cooldownMinutes: p.cooldownMinutes,
                                               schedule: schedule))
                }
                if let limit = p.usageLimitMinutes {
                    newBlocks.append(BlockRule(name: "\(p.name) limit", type: .timer,
                                               appGroupIDs: [groupID()],
                                               cooldownMinutes: p.cooldownMinutes,
                                               usageLimitMinutes: limit,
                                               usageLockMinutes: p.usageLockMinutes))
                }
                if p.schedule == nil && p.usageLimitMinutes == nil {
                    // Manual-only preset → a tag block (toggled by the shared tag).
                    newBlocks.append(BlockRule(name: p.name, type: .tag,
                                               appGroupIDs: [groupID()],
                                               cooldownMinutes: p.cooldownMinutes))
                }
                clearLegacy(presetID: p.id)
            }
        }

        // 2. Legacy NFC tag-flow selection → a "Tag apps" group + a tag block.
        let tagSelection = AppConfigurationStore.shared.selectedApps
        let hasTagApps = !tagSelection.applicationTokens.isEmpty
            || !tagSelection.categoryTokens.isEmpty
            || !tagSelection.webDomainTokens.isEmpty
        if hasTagApps {
            let group = AppGroup(name: "Tag apps", selection: tagSelection)
            newGroups.append(group)
            newBlocks.append(BlockRule(name: "Tag block", type: .tag, appGroupIDs: [group.id]))
        }
        // Clear the legacy unnamed tag-flow stores so nothing lingers.
        ManagedSettingsStore().clearAllSettings()
        ManagedSettingsStore(named: ManagedSettingsStore.Name(rawValue: "tagflow.cats")).clearAllSettings()

        if !newGroups.isEmpty {
            AppGroupStore.shared.replaceAll(AppGroupStore.shared.groups + newGroups)
        }
        if !newBlocks.isEmpty {
            BlockStore.shared.replaceAll(BlockStore.shared.blocks + newBlocks)
        }

        suite.set(true, forKey: SharedDefaults.Keys.migratedToBlocksV2)
        suite.removeObject(forKey: SharedDefaults.Keys.presets)
        #if DEBUG
        DebugLog.shared.log(.state, "migrated \(newGroups.count) groups + \(newBlocks.count) blocks from presets.v1")
        #endif
    }

    #if DEBUG
    /// Encodable mirror of the old BlockingPreset encoding (presets.v1 records).
    private struct LegacyRecord: Encodable {
        let id = UUID()
        var name: String
        var isEnabled = false
        var schedule: BlockingSchedule?
        var cooldownMinutes = 5
        var usageLimitMinutes: Int?
        var usageLockMinutes = 180
        let createdAt = Date()
        var selectionData = (try? JSONEncoder().encode(FamilyActivitySelection())) ?? Data()

        enum CodingKeys: String, CodingKey {
            case id, name, selectionData, isEnabled, schedule, cooldownMinutes, usageLimitMinutes, usageLockMinutes, createdAt
        }
    }

    /// Seed a synthetic presets.v1 blob and reset the migration flag, so launch
    /// exercises the real migration path. Wipes current groups/blocks first.
    static func seedLegacyForTesting() {
        let suite = SharedDefaults.suite
        for block in BlockStore.shared.blocks { BlockStore.shared.delete(id: block.id) }
        for group in AppGroupStore.shared.groups { AppGroupStore.shared.delete(id: group.id) }
        BlockStore.shared.flush(); AppGroupStore.shared.flush()

        let legacy: [LegacyRecord] = [
            LegacyRecord(name: "Old Work", schedule: BlockingSchedule(startHour: 9, startMinute: 0, endHour: 17, endMinute: 0, weekdays: [2,3,4,5,6])),
            LegacyRecord(name: "Old Limiter", usageLimitMinutes: 45),
            LegacyRecord(name: "Old Manual")
        ]
        if let data = try? JSONEncoder().encode(legacy) {
            suite.set(data, forKey: SharedDefaults.Keys.presets)
        }
        suite.set(false, forKey: SharedDefaults.Keys.migratedToBlocksV2)
        DebugLog.shared.log(.state, "seeded legacy presets.v1 for migration test")
    }
    #endif

    /// Best-effort teardown of a legacy preset's runtime state (old key scheme).
    private static func clearLegacy(presetID: UUID) {
        let suite = SharedDefaults.suite
        ManagedSettingsStore(named: ManagedSettingsStore.Name(rawValue: "preset.\(presetID.uuidString)")).clearAllSettings()
        ManagedSettingsStore(named: ManagedSettingsStore.Name(rawValue: "preset.\(presetID.uuidString).cats")).clearAllSettings()
        suite.removeObject(forKey: "running.\(presetID.uuidString)")
        suite.removeObject(forKey: "cooldown.\(presetID.uuidString)")
        suite.removeObject(forKey: "usagelock.\(presetID.uuidString)")
        let names = ["preset.\(presetID.uuidString)", "preset.\(presetID.uuidString).early",
                     "preset.\(presetID.uuidString).late", "usage.\(presetID.uuidString)",
                     "lock.\(presetID.uuidString)"].map { DeviceActivityName(rawValue: $0) }
        DeviceActivityCenter().stopMonitoring(names)
    }

    /// Decoder for the old presets.v1 record (the BlockingPreset type is gone).
    private struct LegacyPreset: Decodable {
        let id: UUID
        let name: String
        let selection: FamilyActivitySelection
        let schedule: BlockingSchedule?
        let cooldownMinutes: Int
        let usageLimitMinutes: Int?
        let usageLockMinutes: Int

        enum CodingKeys: String, CodingKey {
            case id, name, selectionData, schedule, cooldownMinutes, usageLimitMinutes, usageLockMinutes
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            schedule = try c.decodeIfPresent(BlockingSchedule.self, forKey: .schedule)
            cooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 5
            usageLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .usageLimitMinutes)
            usageLockMinutes = try c.decodeIfPresent(Int.self, forKey: .usageLockMinutes) ?? 180
            if let data = try c.decodeIfPresent(Data.self, forKey: .selectionData) {
                selection = (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)) ?? FamilyActivitySelection()
            } else {
                selection = FamilyActivitySelection()
            }
        }
    }
}
