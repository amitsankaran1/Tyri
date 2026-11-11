import SwiftUI
import Combine

struct AdHocBlockView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = AdHocManager.shared
    @StateObject private var groups = AppGroupStore.shared
    @State private var groupID: UUID?
    @State private var minutes = 30
    @State private var customMinutes = 45
    @State private var error: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            if let session = manager.session {
                Section {
                    if session.registered == false {
                        ProgressView("Preparing automatic end…")
                        Text("Blocking starts after iOS confirms the session.").foregroundStyle(.secondary)
                    } else {
                    Label(BlockStatusPresentation.canDisplayActivity ? (manager.enforcementError == nil ? "Blocking on" : "Blocking needs attention") : "Screen Time access needed", systemImage: manager.enforcementError == nil ? "lock.fill" : "exclamationmark.circle")
                        .foregroundStyle(BlockStatusPresentation.canDisplayActivity ? Color.red : Color.secondary)
                    }
                    Text(session.group.name).font(.headline)
                    Text("Session ends at \(session.endsAt.formatted(date: .omitted, time: .shortened))")
                    Text(session.endsAt, style: .timer).monospacedDigit()
                }
                if let issue = manager.enforcementError {
                    Section {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("temporary-session-error")
                    } footer: {
                        Text("This session keeps its original app selection. To use an updated list, end this session and start another.")
                    }
                }
                Section {
                    if let releaseAt = session.releaseAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if releaseAt > context.date {
                                HStack { Text("Stop early in"); Text(releaseAt, style: .timer).monospacedDigit() }
                            } else {
                                Button("Release block", role: .destructive) { manager.release(); dismiss() }
                            }
                        }
                    } else {
                        Button("Stop early…") {
                            do { try manager.requestRelease() } catch { self.error = error.localizedDescription }
                        }
                    }
                } footer: {
                    Text(manager.enforcementError == nil ? "Apps stay blocked during the five-minute wait. Other active blocks still apply after release." : "The session stays active during the five-minute wait. Other active blocks may still apply.")
                }
            } else {
                Section("App list") {
                    if groups.groups.isEmpty {
                        Text("Create a list in the Lists tab first.")
                    } else {
                        Picker("List", selection: $groupID) {
                            Text("Choose a list").tag(nil as UUID?)
                            ForEach(groups.groups) { group in Text(group.name).tag(Optional(group.id)) }
                        }
                        .accessibilityIdentifier("ad-hoc-list")
                    }
                }
                Section("Duration") {
                    Picker("Block for", selection: $minutes) {
                        Text("30 min").tag(30)
                        Text("1 hr").tag(60)
                        Text("2 hr").tag(120)
                        Text("Custom").tag(0)
                    }
                    .accessibilityIdentifier("ad-hoc-duration")
                    if minutes == 0 {
                        Stepper("\(BlockEditorView.minutesLabel(customMinutes))", value: $customMinutes, in: 15...1440, step: 15)
                            .accessibilityIdentifier("custom-block-duration")
                        Text("Choose 15 minutes to 24 hours.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !BlockStatusPresentation.canDisplayActivity {
                    Section { Label("Allow Screen Time access in Settings before starting.", systemImage: "hand.raised") }
                }
                Section {
                    Button(manager.isStarting ? "Starting…" : "Start blocking") {
                        guard let groupID, let group = groups.group(id: groupID) else { return }
                        Task {
                            do { try await manager.start(group: group, minutes: minutes == 0 ? customMinutes : minutes); error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(manager.isStarting || groupID == nil || !BlockStatusPresentation.canDisplayActivity)
                } footer: {
                    Text("Starts now and ends automatically. Uses the apps and websites in this list when you start. To stop early, wait five minutes, then tap Release block.")
                }
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
        }
        .navigationTitle("Block for a while")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            manager.refresh()
            #if DEBUG
            TestHarness.prepareAdHocReleaseWaitForUIReview()
            #endif
        }
        .onReceive(timer) { _ in manager.refresh(reconcile: false) }
    }
}
