import SwiftUI

struct BreakView: View {
    let blockID: UUID
    @Binding var isPresented: Bool
    @StateObject private var breakManager = BreakManager.shared
    @StateObject private var blockStore = BlockStore.shared
    private var block: BlockRule? { blockStore.block(id: blockID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer").font(.largeTitle).foregroundStyle(.tint)
                        Text(block?.name ?? "Break").font(.title2.bold())
                        Text("This block is paused. Other active blocks still apply.").foregroundStyle(.secondary)
                        Text(remainingTime).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                    }
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }
                Section {
                    Button { breakManager.endActiveBreak(); isPresented = false } label: {
                        Label("End break and block apps", systemImage: "lock").frame(maxWidth: .infinity)
                    }
                    .primaryActionButton().listRowBackground(Color.clear)
                } footer: {
                    Text("Blocking resumes automatically when the break ends, even if Tyri is closed. Closing this screen keeps the break running.")
                }
            }
            .navigationTitle("Break").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented = false } } }
        }
        .onAppear { startIfNeeded() }
        .onChange(of: breakManager.activeBreak) { active in if active == nil { isPresented = false } }
    }
    private var remainingTime: String {
        let seconds = max(0, Int(breakManager.remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func startIfNeeded() {
        // Already on this block's break (reopened from the editor/home) — just show it.
        if breakManager.activeBreak?.blockID == blockID { return }
        guard let block = block, breakManager.isBreakAvailable(for: block) else {
            isPresented = false
            return
        }
        breakManager.start(for: block)
        // start() can no-op (e.g. rules changed underneath us) — don't show a dead sheet.
        if breakManager.activeBreak?.blockID != blockID {
            isPresented = false
        }
    }
}
