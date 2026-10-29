import SwiftUI

extension View {
    @ViewBuilder
    func primaryActionButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}

enum BlockTypeStyle {
    static func title(_ type: BlockType) -> String {
        switch type {
        case .schedule: return "Schedule"
        case .timer: return "Usage limit"
        case .tag: return "NFC tag"
        }
    }
    static func icon(_ type: BlockType) -> String {
        switch type {
        case .schedule: return "clock"
        case .timer: return "hourglass"
        case .tag: return "sensor.tag.radiowaves.forward"
        }
    }
}

struct SelectionPlaceholder: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title2.bold())
            Text(description).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
