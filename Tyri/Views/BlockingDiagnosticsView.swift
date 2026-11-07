import SwiftUI
import DeviceActivity
import FamilyControls

struct BlockingDiagnosticsView: View {
    @State private var report = ""
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
    }
    private func refresh() {
        let info = Bundle.main.infoDictionary ?? [:]
        let center = DeviceActivityCenter()
        let blocks = BlockStore.shared.blocks
        let groups = AppGroupStore.shared.groups
        var lines = ["Tyri \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))",
                     "iOS \(UIDevice.current.systemVersion)", "Captured: \(ISO8601DateFormatter().string(from: Date()))",
                     "Authorization: \(AuthorizationCenter.shared.authorizationStatus)",
                     "Registered activities: \(center.activities.count)", "Lists: \(groups.count); blocks: \(blocks.count)",
                     "Settings readback is not proof of effective shielding."]
        for block in blocks {
            let tokens = BlockResolution.tokens(for: block, groups: groups)
            let activity = UsageMonitoring.usageActivityName(for: block.id)
            lines += ["", "Block: \(block.name) [\(block.id.uuidString.prefix(8))]",
                      "Type: \(block.type); manual: \(block.isEnabled)",
                      "Targets: \(tokens.apps.count) apps, \(tokens.categories.count) categories, \(tokens.webDomains.count) web tokens, \(tokens.domains.count) typed domains",
                      "Referenced lists: \(block.appGroupIDs.count); missing: \(block.appGroupIDs.filter { id in !groups.contains { $0.id == id } }.count)",
                      "Allowance/lock: \(block.usageLimitMinutes ?? 0)/\(block.usageLockMinutes) min",
                      "Usage monitor registered: \(center.activities.contains(activity))",
                      "Usage event count: \(center.activities.contains(activity) ? center.events(for: activity).count : 0)",
                      "Schedule registered: \(center.activities.contains(SchedulingManager.activityName(for: block.id)))",
                      "Schedule: \(block.schedule?.summary ?? "none")",
                      "Lock deadline: \(SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: block.id)) ?? "none")",
                      "Last shield audit: \(SharedDefaults.suite.string(forKey: SharedDefaults.Keys.shieldAudit(blockID: block.id)) ?? "none")"]
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
