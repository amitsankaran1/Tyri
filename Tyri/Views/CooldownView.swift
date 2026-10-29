import SwiftUI

struct CooldownView: View {
    let blockID: UUID
    @Binding var isPresented: Bool
    @StateObject private var cooldown = CooldownManager.shared
    @StateObject private var blockStore = BlockStore.shared
    private var block: BlockRule? { blockStore.block(id: blockID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(.tint)
                        Text("Disable \(block?.name ?? "block")?").font(.title2.bold())
                        Text(cooldown.isComplete ? "You can now release this block." : "Your apps stay blocked while you wait.")
                            .foregroundStyle(.secondary)
                        Text(remainingTime).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                    }
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }
                Section {
                    Button { cooldown.complete(); isPresented = false } label: {
                        Label("Release block", systemImage: "lock.open").frame(maxWidth: .infinity)
                    }
                    .primaryActionButton().disabled(!cooldown.isComplete).listRowBackground(Color.clear)
                } footer: { Text("Closing this screen cancels the cooldown. Your schedules and usage limits remain configured.") }
            }
            .navigationTitle("Cooldown").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cooldown.cancel(); isPresented = false }
                }
            }
        }
        .onAppear { startIfNeeded() }
        .onDisappear { if cooldown.activeCooldown?.blockID == blockID { cooldown.cancel() } }
    }
    private var remainingTime: String {
        let seconds = max(0, Int(cooldown.remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func startIfNeeded() {
        // If a cooldown for this block is already running, leave it alone.
        if cooldown.activeCooldown?.blockID == blockID { return }
        let minutes = block?.cooldownMinutes ?? 5
        // "No cooldown" blocks have no early-disable path at all — this sheet
        // should be unreachable for them; dismiss without releasing anything.
        guard minutes > 0 else {
            isPresented = false
            return
        }
        cooldown.start(for: blockID, minutes: minutes)
    }
}
