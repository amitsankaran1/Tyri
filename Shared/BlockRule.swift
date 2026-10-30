//
//  BlockRule.swift
//  Tyri
//
//  A single blocking rule of one type (schedule, timer, or NFC tag) applied to
//  one or more AppGroups. The effective shield is the union of the referenced
//  groups' tokens (see BlockResolution). UI label: "Block".
//
//  Each block uses its own `ManagedSettingsStore(named: "block.<UUID>")` so
//  blocks shield independently; iOS unions all stores' shields.
//
//  Add target membership to BOTH Tyri and TyriMonitor targets.
//

import Foundation
import FamilyControls

enum BlockType: String, Codable {
    case schedule   // time-of-day window
    case timer      // cumulative usage budget → timed lockout
    case tag        // toggled by tapping the registered NFC tag
}

struct BlockRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: BlockType
    /// Referenced AppGroup ids; effective tokens = union of their selections.
    var appGroupIDs: [UUID]
    /// Manual force-on (and the on/off state for `.tag` blocks).
    var isEnabled: Bool
    /// Early-release friction in minutes (all block types). `0` is the strictest
    /// setting — "no cooldown" — meaning there is NO in-app early-disable path
    /// while the block is active (it lifts only when its schedule window or
    /// usage lockout ends, via the NFC tag for tag blocks, or via the emergency
    /// override).
    var cooldownMinutes: Int
    /// Length of the single break allowed per activation (schedule window / tag
    /// session), in minutes. `0` — the default — means no breaks. Meaningful for
    /// `.schedule` and `.tag` blocks only; `.timer` lockouts never offer breaks.
    var breakMinutes: Int
    /// When `type == .schedule`.
    var schedule: BlockingSchedule?
    /// Cumulative daily usage budget in minutes (when `type == .timer`).
    var usageLimitMinutes: Int?
    /// How long the lockout lasts once the budget is hit (when `type == .timer`).
    var usageLockMinutes: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: BlockType = .schedule,
        appGroupIDs: [UUID] = [],
        isEnabled: Bool = false,
        cooldownMinutes: Int = 5,
        breakMinutes: Int = 0,
        schedule: BlockingSchedule? = nil,
        usageLimitMinutes: Int? = nil,
        usageLockMinutes: Int = 180,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.appGroupIDs = appGroupIDs
        self.isEnabled = isEnabled
        self.cooldownMinutes = cooldownMinutes
        self.breakMinutes = breakMinutes
        self.schedule = schedule
        self.usageLimitMinutes = usageLimitMinutes
        self.usageLockMinutes = usageLockMinutes
        self.createdAt = createdAt
    }

    static func == (lhs: BlockRule, rhs: BlockRule) -> Bool {
        let a = lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.type == rhs.type
            && lhs.isEnabled == rhs.isEnabled
            && lhs.cooldownMinutes == rhs.cooldownMinutes
            && lhs.breakMinutes == rhs.breakMinutes
        let b = lhs.schedule == rhs.schedule
            && lhs.usageLimitMinutes == rhs.usageLimitMinutes
            && lhs.usageLockMinutes == rhs.usageLockMinutes
            && lhs.createdAt == rhs.createdAt
            && lhs.appGroupIDs == rhs.appGroupIDs
        return a && b
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, appGroupIDs, isEnabled, schedule, cooldownMinutes
        case breakMinutes, usageLimitMinutes, usageLockMinutes, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decodeIfPresent(BlockType.self, forKey: .type) ?? .schedule
        appGroupIDs = try c.decodeIfPresent([UUID].self, forKey: .appGroupIDs) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        schedule = try c.decodeIfPresent(BlockingSchedule.self, forKey: .schedule)
        cooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 5
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 0
        usageLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .usageLimitMinutes)
        usageLockMinutes = try c.decodeIfPresent(Int.self, forKey: .usageLockMinutes) ?? 180
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(appGroupIDs, forKey: .appGroupIDs)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encodeIfPresent(schedule, forKey: .schedule)
        try c.encode(cooldownMinutes, forKey: .cooldownMinutes)
        try c.encode(breakMinutes, forKey: .breakMinutes)
        try c.encodeIfPresent(usageLimitMinutes, forKey: .usageLimitMinutes)
        try c.encode(usageLockMinutes, forKey: .usageLockMinutes)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
