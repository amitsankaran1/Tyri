import Foundation

/// The UI depends on this contract, not on a particular inference provider.
protocol BlockDescriptionExtracting {
    func interpret(_ request: DescriptionRequest) async throws -> BlockDescriptionDraft
}

@MainActor
final class DescriptionService: BlockDescriptionExtracting {
    static let shared = DescriptionService()
    static var isFixture: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TYRI_DESCRIPTION_FIXTURE"] != nil
        #else
        return false
        #endif
    }

    func interpret(_ request: DescriptionRequest) async throws -> BlockDescriptionDraft {
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["TYRI_DESCRIPTION_FIXTURE"] {
            try await Task.sleep(nanoseconds: 150_000_000)
            if fixture == "failure" { throw DescriptionError.message("The model service is unavailable. Your description is still here; retry or use the manual editor.") }
            let reference = request.lists.first { $0.name == "Social media" } ?? request.lists.first
            let refs: [BlockDescriptionDraft.ListReference] = fixture == "missing"
                ? [.init(existingID: nil, name: "Shopping")]
                : [.init(existingID: reference?.id, name: reference?.name ?? "Social media")]
            return BlockDescriptionDraft(name: "Focus time", lists: refs, type: fixture == "usage" ? "timer" : "schedule",
                                         schedule: fixture == "usage" ? nil : .init(weekdays: [2,3,4,5,6], startMinute: 555, endMinute: 1000, allDay: false),
                                         usageMinutes: fixture == "usage" ? 40 : nil, lockoutMinutes: fixture == "usage" ? 50 : nil,
                                         cooldownMinutes: nil, breakMinutes: nil,
                                         clarification: fixture == "clarify" ? "Do you mean 9am–11am or 9pm–11pm? Add AM or PM to your description." : nil,
                                         unsupportedReason: fixture == "unsupported" ? "One-time dates aren't supported here yet. Choose a weekly schedule or use Block for a while." : nil)
        }
        #endif
        return try await AttestedDescriptionTransport.shared.interpret(request)
    }
}
