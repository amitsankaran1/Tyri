//
//  Migration.swift
//  Tyri
//
//  One-time migration from the old preset model (presets.v1, apps embedded in
//  each preset) to the new App Groups + Blocks model. Runs once on launch.
//

import Foundation
import CryptoKit
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
enum Migration {

    static func runIfNeeded() {
        // The common (already migrated) launch path is a read only check. It
        // must not wait on a foreground worker's interprocess lease.
        guard !SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.migratedToBlocksV2) else { return }
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }
        let suite = SharedDefaults.suite
        guard !suite.bool(forKey: SharedDefaults.Keys.migratedToBlocksV2) else { return }

        var newGroups: [AppGroup] = []
        var newBlocks: [BlockRule] = []

        // Decode before changing anything. An unreadable input must survive retry.
        let legacy: [LegacyPreset]
        if let data = suite.data(forKey: SharedDefaults.Keys.presets) {
            guard let decoded = try? JSONDecoder().decode([LegacyPreset].self, from: data) else { return }
            legacy = decoded
        } else { legacy = [] }
        // Stable identities make interrupted group/block writes safe to retry.
        do {
            for p in legacy {
                let group = AppGroup(id: migratedID("group", source: p.id.uuidString), name: p.name, selection: p.selection)
                var groupAdded = false
                func groupID() -> UUID {
                    if !groupAdded { newGroups.append(group); groupAdded = true }
                    return group.id
                }
                if let schedule = p.schedule {
                    newBlocks.append(BlockRule(id: migratedID("schedule", source: p.id.uuidString), name: p.name, type: .schedule,
                                               appGroupIDs: [groupID()], isEnabled: p.isEnabled,
                                               cooldownMinutes: p.cooldownMinutes,
                                               schedule: schedule))
                }
                if let limit = p.usageLimitMinutes {
                    newBlocks.append(BlockRule(id: migratedID("timer", source: p.id.uuidString), name: "\(p.name) limit", type: .timer,
                                               appGroupIDs: [groupID()], isEnabled: p.isEnabled,
                                               cooldownMinutes: p.cooldownMinutes,
                                               usageLimitMinutes: limit,
                                               usageLockMinutes: p.usageLockMinutes))
                }
                if p.schedule == nil && p.usageLimitMinutes == nil {
                    // Manual-only preset → a tag block (toggled by the shared tag).
                    newBlocks.append(BlockRule(id: migratedID("tag", source: p.id.uuidString), name: p.name, type: .tag,
                                               appGroupIDs: [groupID()], isEnabled: p.isEnabled,
                                               cooldownMinutes: p.cooldownMinutes))
                }
            }
        }

        // 2. Legacy NFC tag-flow selection → a "Tag apps" group + a tag block.
        let tagSelection = AppConfigurationStore.shared.selectedApps
        let hasTagApps = !tagSelection.applicationTokens.isEmpty
            || !tagSelection.categoryTokens.isEmpty
            || !tagSelection.webDomainTokens.isEmpty
        if hasTagApps {
            let group = AppGroup(id: migratedID("group", source: "legacy-tag"), name: "Tag apps", selection: tagSelection)
            newGroups.append(group)
            newBlocks.append(BlockRule(id: migratedID("tag", source: "legacy-tag"), name: "Tag block", type: .tag, appGroupIDs: [group.id], isEnabled: AppConfigurationStore.shared.isBlockingEnabled))
        }
        if !newGroups.isEmpty {
            AppGroupStore.shared.replaceAll(AppGroupStore.shared.groups + newGroups.filter { item in !AppGroupStore.shared.groups.contains { $0.id == item.id } })
        }
        if !newBlocks.isEmpty {
            BlockStore.shared.replaceAll(BlockStore.shared.blocks + newBlocks.filter { item in !BlockStore.shared.blocks.contains { $0.id == item.id } })
        }

        // Only tear down old enforcement after replacements are persisted.
        for block in BlockStore.shared.blocks where newBlocks.contains(where: { $0.id == block.id }) && block.isEnabled {
            BlockingActuator.start(blockID: block.id, bypassWeekday: true, setRunningFlag: false)
        }
        for preset in legacy { clearLegacy(presetID: preset.id) }
        ManagedSettingsStore().clearAllSettings()
        ManagedSettingsStore(named: ManagedSettingsStore.Name(rawValue: "tagflow.cats")).clearAllSettings()
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

    private static func migratedID(_ kind: String, source: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("tyri-v2:\(kind):\(source)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

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
        let isEnabled: Bool
        let selection: FamilyActivitySelection
        let schedule: BlockingSchedule?
        let cooldownMinutes: Int
        let usageLimitMinutes: Int?
        let usageLockMinutes: Int

        enum CodingKeys: String, CodingKey {
            case id, name, isEnabled, selectionData, schedule, cooldownMinutes, usageLimitMinutes, usageLockMinutes
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            schedule = try c.decodeIfPresent(BlockingSchedule.self, forKey: .schedule)
            cooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 5
            usageLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .usageLimitMinutes)
            usageLockMinutes = try c.decodeIfPresent(Int.self, forKey: .usageLockMinutes) ?? 180
            if let data = try c.decodeIfPresent(Data.self, forKey: .selectionData) {
                selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            } else {
                selection = FamilyActivitySelection()
            }
        }
    }
}
