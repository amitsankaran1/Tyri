import SwiftUI

/// Keeps the next step beside the failure instead of requiring users to find a
/// separate warning elsewhere on Focus. Navigation uses saved lists, not drafts.
struct BlockRecoverySection: View {
    let block: BlockRule
    var onRetry: () -> Void
    var openSettings: () -> Void
    @StateObject private var groups = AppGroupStore.shared

    private var lists: [AppGroup] { groups.groups.filter { block.appGroupIDs.contains($0.id) } }
    private var instructions: String {
        if !BlockStatusPresentation.canDisplayActivity {
            return "Open Screen Time settings below, tap Allow Screen Time access, then return to this block."
        }
        if lists.isEmpty {
            return "Select an app list under App lists below, then tap Save block. If you don't have a list yet, create one in the Lists tab."
        }
        let tokens = BlockResolution.tokens(for: block, groups: groups.groups)
        if tokens.apps.count > BlockingActuator.maxChunksPerBlock * BlockingActuator.tokensPerStore || tokens.webDomains.count > BlockingActuator.maxChunksPerBlock * BlockingActuator.tokensPerStore {
            return ScreenTimeManager.shared.isBlockActive(block)
                ? "This selection is too large. Stop the block before reducing the selected apps or websites in its lists. Use Stop early, or Settings → Emergency Access if early stopping is unavailable."
                : "Open a list below and reduce the selected apps or websites, then save the list and retry blocking."
        }
        if tokens.isEmpty && (block.type == .timer || tokens.domains.isEmpty) {
            return block.type == .timer
                ? "Open a list below, tap Select apps, choose apps in the Screen Time picker, then save. Typed website addresses alone cannot measure usage."
                : "Open a list below, choose apps or add websites, then save the list and retry blocking."
        }
        return "Tap Retry blocking to restore this block. If the warning remains, check Screen Time settings, then open Blocking diagnostics and share the report for help. Retrying preserves a healthy usage allowance."
    }

    var body: some View {
        Section("What to do") {
            Text(instructions)
                .accessibilityIdentifier("block-recovery-instructions")
            if BlockStatusPresentation.canDisplayActivity {
                ForEach(lists) { list in
                    NavigationLink("Edit \(list.name)") { AppGroupEditorView(groupID: list.id) }
                        .accessibilityIdentifier("recovery-list-\(list.id)")
                }
                Button("Retry blocking") {
                    if !BlockingRecovery.retry(blockID: block.id) { openSettings() }
                    onRetry()
                }
                .accessibilityIdentifier("retry-blocking")
            }
            Button("Screen Time settings", action: openSettings)
            NavigationLink("Blocking diagnostics") { BlockingDiagnosticsView() }
        }
    }
}
