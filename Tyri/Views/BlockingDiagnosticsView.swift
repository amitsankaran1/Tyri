import SwiftUI
import DeviceActivity
import FamilyControls

struct BlockingDiagnosticsView: View {
    @State private var report = ""
    @State private var refreshTask: Task<Void, Never>?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            Section {
                Text("Capture this after a block fails. It shows permission, monitor and shield-setting status; matching settings alone do not prove that iOS blocked an app.")
                Button("Refresh diagnostics", action: refresh)
                ShareLink("Share diagnostics", item: report)
            } footer: {
                Text("Includes block names and timing settings. Does not include selected app identities, tokens or browsing history.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("On-device report") {
                Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .accessibilityIdentifier("blocking-diagnostics-report")
            }
        }
            .padding()
        }
        .navigationTitle("Blocking diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onDisappear { refreshTask?.cancel() }
    }
    private func refresh() {
        refreshTask?.cancel()
        if report.isEmpty { report = "Checking Screen Time registrations…" }
        refreshTask = Task {
            let native = await Task.detached {
                let center = DeviceActivityCenter()
                let activities = center.activities
                return Dictionary(uniqueKeysWithValues: activities.map { ($0.rawValue, center.events(for: $0).count) })
            }.value
            guard !Task.isCancelled else { return }
            let info = Bundle.main.infoDictionary ?? [:]
            let blocks = BlockStore.shared.blocks
            let groups = AppGroupStore.shared.groups
            var lines = ["Tyri \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))",
                         "iOS \(UIDevice.current.systemVersion)", "Captured: \(ISO8601DateFormatter().string(from: Date()))",
                         "Authorization: \(AuthorizationCenter.shared.authorizationStatus)",
                         "Registered activities: \(native.count)", "Lists: \(groups.count); blocks: \(blocks.count)",
                         "Settings readback is not proof of effective shielding."]
            if let error = BlockStore.shared.loadError ?? AppGroupStore.shared.loadError { lines.append("Saved data: \(error)") }
            if AuthorizationCenter.shared.authorizationStatus != .approved {
                lines.append("Screen Time is not authorized. Any matched readback below describes saved settings only; it does not establish protection.")
            }
            if let session = AdHocMonitoring.session {
                lines += ["Temporary session: \(session.id.uuidString.prefix(8)); registered: \(session.registered != false)",
                          "Temporary session deadline: \(session.endsAt)",
                          "Temporary registration pending: \(MonitorRegistration.pending("adhoc.\(session.id.uuidString)") != nil)"]
            } else { lines.append("Temporary session: none") }
            for block in blocks {
                let tokens = BlockResolution.tokens(for: block, groups: groups)
                let activity = UsageMonitoring.usageActivityName(for: block.id)
                lines += ["", "Block: \(block.name) [\(block.id.uuidString.prefix(8))]",
                          "Type: \(block.type); manual: \(block.isEnabled)",
                          "Targets: \(tokens.apps.count) apps, \(tokens.categories.count) categories, \(tokens.webDomains.count) web tokens, \(tokens.domains.count) typed domains",
                          "Referenced lists: \(block.appGroupIDs.count); missing: \(block.appGroupIDs.filter { id in !groups.contains { $0.id == id } }.count)",
                          "Allowance/lock: \(block.usageLimitMinutes ?? 0)/\(block.usageLockMinutes) min",
                          "Usage monitor registered: \(native[activity.rawValue] != nil)",
                          "Usage event count: \(native[activity.rawValue] ?? 0)",
                          "Schedule registered: \(native[SchedulingManager.activityName(for: block.id).rawValue] != nil)",
                          "Schedule: \(block.schedule?.summary ?? "none")",
                          "Lock deadline: \(SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) ?? "none")",
                          "Last shield audit: \(SharedDefaults.suite.string(forKey: SharedDefaults.Keys.shieldAudit(blockID: block.id)) ?? "none")"]
                lines += ["Break deadline: \(BreakMonitoring.breakEnd(blockID: block.id)?.description ?? "none")",
                          "Break awaiting confirmation: \(BreakMonitoring.pendingEnd(blockID: block.id)?.description ?? "none")",
                          "Break used this activation: \(BreakMonitoring.breakUsed(blockID: block.id))"]
                for prefix in ["block", "usage", "lock", "break"] {
                    lines.append("\(prefix) registration pending: \(MonitorRegistration.pending("\(prefix).\(block.id.uuidString)") != nil)")
                }
                if tokens.isEmpty && tokens.domains.isEmpty { lines.append("No targets: matching empty settings does not establish protection.") }
                for key in [SharedDefaults.Keys.shieldError(blockID: block.id), SharedDefaults.Keys.usageError(blockID: block.id), SharedDefaults.Keys.usageLockError(blockID: block.id)] {
                    if let error = SharedDefaults.suite.string(forKey: key) { lines.append("Error: \(error)") }
                }
                if let error = SchedulingManager.shared.registrationErrors[block.id] { lines.append("Schedule error: \(error)") }
                for event in EnforcementDiagnostics.events {
                    if let value = SharedDefaults.suite.string(forKey: EnforcementDiagnostics.key(event, block.id)) { lines.append("\(event): \(value)") }
                }
            }
            report = lines.joined(separator: "\n")
        }
    }
}
