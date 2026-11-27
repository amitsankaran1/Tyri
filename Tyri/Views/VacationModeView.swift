import SwiftUI

extension VacationPlan {
    /// "Tue, Dec 2, 6:00 AM". Adds the chosen zone, and the local time, when the
    /// phone is in a different time zone than the one the plan was set in.
    func resumeDescription(in current: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMdjmm")
        formatter.timeZone = timeZone
        var text = formatter.string(from: resumeAt)
        guard timeZone.secondsFromGMT(for: resumeAt) != current.secondsFromGMT(for: resumeAt) else { return text }
        text += " " + (timeZone.abbreviation(for: resumeAt) ?? timeZoneID)
        let local = DateFormatter()
        local.setLocalizedDateFormatFromTemplate("EEEjmm")
        local.timeZone = current
        return text + " (\(local.string(from: resumeAt)) here)"
    }
}

/// Pause selected blocks' automatic activation until a fixed date and time.
struct VacationModeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var blockStore = BlockStore.shared
    @State private var plan = VacationMode.pendingPlan()
    @State private var editing = VacationMode.pendingPlan() == nil
    @State private var selected: Set<UUID> = []
    @State private var resumeAt = VacationModeView.defaultResume()
    @State private var failed = false

    /// Tag blocks only start when you tap your tag, so there's nothing automatic to pause.
    private var pausable: [BlockRule] { blockStore.blocks.filter { $0.type != .tag } }
    private var allSelected: Bool { !pausable.isEmpty && Set(pausable.map(\.id)).isSubset(of: selected) }
    private var earliest: Date { Date().addingTimeInterval(15 * 60) }

    var body: some View {
        Form {
            if let plan, !editing {
                activeSections(plan)
            } else if pausable.isEmpty {
                Section {
                    Text("Vacation mode pauses scheduled and usage-limit blocks. You don't have any yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                editorSections
            }
        }
        .navigationTitle("Vacation mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if editing && plan != nil {
                    Button("Cancel") { editing = false }
                } else {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Couldn't start vacation", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose at least one block and a return time in the future, then try again.")
        }
    }

    @ViewBuilder
    private func activeSections(_ plan: VacationPlan) -> some View {
        Section {
            Label("Resumes \(plan.resumeDescription())", systemImage: "airplane")
                .font(.headline)
                .accessibilityIdentifier("vacation-resume")
            if let error = SharedDefaults.suite.string(forKey: VacationMode.errorKey) {
                Text(error).font(.subheadline).foregroundStyle(.orange)
            }
        } footer: {
            Text("Blocking resumes on its own at this time, even if Tyri is closed. Turning a block on yourself still works during vacation.")
        }
        Section("Paused") {
            ForEach(blockStore.blocks.filter { plan.blockIDs.contains($0.id) }) { block in
                Label(block.name, systemImage: BlockTypeStyle.icon(block.type))
            }
        }
        Section {
            Button("Change vacation") {
                selected = plan.blockIDs
                resumeAt = plan.resumeAt
                editing = true
            }
            Button("End vacation now") {
                VacationMode.end()
                ForegroundRecovery.shared.requestAccepted()
                dismiss()
            }
            .accessibilityIdentifier("end-vacation")
        } footer: {
            Text("Ending now restores every paused block's normal schedule and limits right away.")
        }
    }

    @ViewBuilder
    private var editorSections: some View {
        Section {
            Toggle("All blocks", isOn: Binding(
                get: { allSelected },
                set: { selected = $0 ? Set(pausable.map(\.id)) : [] }))
            ForEach(pausable) { block in
                Toggle(isOn: Binding(
                    get: { selected.contains(block.id) },
                    set: { if $0 { selected.insert(block.id) } else { selected.remove(block.id) } })) {
                    Label(block.name, systemImage: BlockTypeStyle.icon(block.type))
                }
            }
        } header: {
            Text("Pause")
        } footer: {
            Text("Paused blocks won't start on their schedule or lock when you reach a usage limit. A block that's on right now stays on until it ends normally. Blocks you don't choose keep working.")
        }
        Section {
            DatePicker("Resume", selection: $resumeAt, in: earliest..., displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("vacation-resume-picker")
        } footer: {
            Text("Normal blocking returns at this time in \(TimeZone.current.localizedName(for: .generic, locale: .current) ?? TimeZone.current.identifier), even if you travel.")
        }
        Section {
            Button(plan == nil ? "Start vacation" : "Update vacation") {
                guard VacationMode.start(blockIDs: selected, resumeAt: resumeAt) != nil else { failed = true; return }
                ForegroundRecovery.shared.requestAccepted()
                plan = VacationMode.pendingPlan()
                editing = false
            }
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("start-vacation")
        }
    }

    /// 6:00 AM one week from today.
    static func defaultResume(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 6, minute: 0, second: 0, of: day) ?? day
    }
}
