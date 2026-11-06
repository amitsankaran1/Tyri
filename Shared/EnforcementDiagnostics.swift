import Foundation

/// Bounded, on-device troubleshooting records. No app tokens or browsing history.
enum EnforcementDiagnostics {
    static let events = ["callback", "threshold", "registration", "shield", "recovery"]
    static func key(_ event: String, _ blockID: UUID) -> String { "enforcementDiagnostic.\(blockID.uuidString).\(event)" }
    static func record(_ event: String, blockID: UUID, detail: String) {
        guard events.contains(event) else { return }
        SharedDefaults.suite.set("\(ISO8601DateFormatter().string(from: Date())) · \(detail.prefix(600))", forKey: key(event, blockID))
    }
}
