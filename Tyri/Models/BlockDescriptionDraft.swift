import Foundation

/// Provider-neutral interpretation. No runtime IDs, tokens or activation state from a model.
struct BlockDescriptionDraft: Codable {
    struct ListReference: Codable { var existingID: String?; var name: String }
    struct Weekly: Codable { var weekdays: [Int]; var startMinute: Int; var endMinute: Int; var allDay: Bool }
    var name: String
    var lists: [ListReference]
    var type: String?
    var schedule: Weekly?
    var usageMinutes: Int?
    var lockoutMinutes: Int?
    var cooldownMinutes: Int?
    var breakMinutes: Int?
    var clarification: String?
    var unsupportedReason: String?

    func validate() throws {
        if let reason = unsupportedReason { throw DescriptionError.message(reason) }
        if let question = clarification { throw DescriptionError.message(question) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              !lists.isEmpty, lists.count <= 50,
              lists.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 100 }),
              let type, ["schedule", "timer", "tag"].contains(type) else { throw DescriptionError.invalid }
        for value in [cooldownMinutes, breakMinutes].compactMap({ $0 }) {
            guard (0...60).contains(value) else { throw DescriptionError.invalid }
        }
        switch type {
        case "schedule":
            guard let schedule, !schedule.weekdays.isEmpty, Set(schedule.weekdays).count == schedule.weekdays.count,
                  schedule.weekdays.allSatisfy({ (1...7).contains($0) }),
                  (0..<1440).contains(schedule.startMinute), (0..<1440).contains(schedule.endMinute),
                  (schedule.startMinute == schedule.endMinute) == schedule.allDay,
                  usageMinutes == nil, lockoutMinutes == nil else { throw DescriptionError.invalid }
            let length = (schedule.endMinute - schedule.startMinute + 1440) % 1440
            guard length == 0 || length >= 15 else { throw DescriptionError.message("Schedules need a window of at least 15 minutes.") }
        case "timer":
            guard schedule == nil, let usageMinutes, let lockoutMinutes,
                  (5...1435).contains(usageMinutes), (5...1435).contains(lockoutMinutes),
                  usageMinutes.isMultiple(of: 5), lockoutMinutes.isMultiple(of: 5),
                  (breakMinutes ?? 0) == 0 else { throw DescriptionError.invalid }
        default:
            guard schedule == nil, usageMinutes == nil, lockoutMinutes == nil else { throw DescriptionError.invalid }
        }
    }
}

enum DescriptionError: LocalizedError {
    case message(String)
    case invalid
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .invalid: return "This interpretation needs another look. Rephrase your request or use the manual editor."
        }
    }
}

struct DescriptionRequest: Codable {
    struct SavedList: Codable { let id: String; let name: String }
    let text: String
    let lists: [SavedList]
    let timeZone: String
    let locale: String
}
