import SwiftUI

/// A duration, never a date or a time of day. Edits commit only with Done.
struct UsageDurationPicker: View {
    let title: String
    @Binding var minutes: Int
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(Self.label(minutes)).monospacedDigit()
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(Self.label(minutes))
        .accessibilityIdentifier(title == "Allow usage for" ? "usage-duration" : "lock-duration")
        .sheet(isPresented: $editing) {
            DurationEditor(title: title, initial: minutes) { minutes = $0 }
        }
    }

    static func label(_ minutes: Int) -> String {
        BlockEditorView.minutesLabel(minutes)
    }
}

private struct DurationEditor: View {
    let title: String
    let commit: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int
    @State private var minutes: Int

    init(title: String, initial: Int, commit: @escaping (Int) -> Void) {
        self.title = title
        self.commit = commit
        // Existing exact values are untouched unless the user confirms an edit.
        let draft = min(1435, max(5, ((initial + 4) / 5) * 5))
        _hours = State(initialValue: draft / 60)
        _minutes = State(initialValue: draft % 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(UsageDurationPicker.label(hours * 60 + minutes))
                    .font(.largeTitle.monospacedDigit()).accessibilityIdentifier("duration-preview")
                HStack {
                    Picker("Hours", selection: $hours) {
                        ForEach(0..<24) { Text("\($0) hr").tag($0) }
                    }
                    .accessibilityIdentifier("duration-hours")
                    Picker("Minutes", selection: $minutes) {
                        ForEach(Array(stride(from: hours == 0 ? 5 : 0, through: 55, by: 5)), id: \.self) {
                            Text("\($0) min").tag($0)
                        }
                    }
                    .accessibilityIdentifier("duration-minutes")
                }.pickerStyle(.wheel)
                Text("Hours and minutes · 5 minutes to 23 hours 55 minutes")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .onChange(of: hours) { value in
                if value == 0 && minutes == 0 { minutes = 5 }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit(max(5, hours * 60 + minutes)); dismiss() }
                }
            }
        }
    }
}
