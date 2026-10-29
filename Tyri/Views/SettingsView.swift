import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var config = AppConfigurationStore.shared
    @StateObject private var screenTime = ScreenTimeManager.shared
    @State private var requesting = false
    @State private var authorizationError: String?
    @State private var showChallenge = false
    #if DEBUG
    @State private var showDebug = false
    #endif

    var body: some View {
        Form {
            Section {
                LabeledContent("Screen Time", value: screenTime.authorizationStatus == .approved ? "Allowed" : "Not allowed")
                if screenTime.authorizationStatus != .approved {
                    Button {
                        Task {
                            requesting = true
                            defer { requesting = false }
                            do { try await screenTime.requestAuthorization() }
                            catch { authorizationError = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            Text(requesting ? "Requesting access…" : "Allow Screen Time access")
                            if requesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(requesting)
                }
            } header: { Text("Permissions") } footer: {
                Text("Tyri uses Screen Time to block the apps and websites you choose.")
            }
            Section {
                NavigationLink { TagRegistrationView() } label: {
                    LabeledContent("NFC tag", value: config.isTagRegistered ? "Connected" : "Not connected")
                }
            } header: { Text("Blocking tag") } footer: {
                Text("Scan your tag in Tyri to turn all tag blocks on or off together.")
            }
            if screenTime.authorizationStatus == .approved {
                Section {
                    Button { showChallenge = true } label: {
                        Label("Start typing challenge", systemImage: "keyboard")
                    }
                } header: { Text("Emergency Access") } footer: {
                    Text("Complete the passage to clear current blocks without your tag. Schedules and usage limits can activate again.")
                }
            }
            Section {
                LabeledContent("Version", value: version)
            }
            #if DEBUG
            Section("Developer") {
                NavigationLink("Debug menu") { DebugMenuView() }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $showChallenge) { TypingChallengeView(isPresented: $showChallenge) }
        .alert("Screen Time access failed", isPresented: Binding(
            get: { authorizationError != nil }, set: { if !$0 { authorizationError = nil } }
        )) { Button("OK", role: .cancel) { authorizationError = nil } }
        message: { Text(authorizationError ?? "Please try again.") }
        .onAppear { screenTime.checkAuthorizationStatus() }
        #if DEBUG
        .fullScreenCover(isPresented: $showDebug) {
            NavigationStack {
                DebugMenuView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Close") { showDebug = false } }
                }
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["BLOCK_OPEN_DEBUG_MENU"] == "1" { showDebug = true }
        }
        #endif
    }
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
    }
}
