import SwiftUI

struct ScheduleRegistrationWarning: View {
    let block: BlockRule
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Schedule needs attention: \(block.name)", systemImage: "exclamationmark.triangle")
                .font(.headline).foregroundStyle(.orange)
            Text(message).font(.subheadline)
            Text("Your settings are saved, but automatic starts and stops may not work. Allow Screen Time access in Settings, then retry.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Retry schedule") { SchedulingManager.shared.applySchedule(for: block) }
        }
        .accessibilityIdentifier("schedule-registration-error")
    }
}
