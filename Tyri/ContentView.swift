import SwiftUI

struct ContentView: View {
    @State private var selection = 0
    @StateObject private var blocks = BlockStore.shared
    @StateObject private var lists = AppGroupStore.shared
    @StateObject private var recovery = ForegroundRecovery.shared

    var body: some View {
        TabView(selection: $selection) {
            HomeView(openLists: { selection = 1 })
                .tabItem { Label("Focus", systemImage: "lock.shield") }
                .tag(0)
            AppGroupListView()
                .tabItem { Label("Lists", systemImage: "square.grid.2x2") }
                .tag(1)
        }
        .tint(.blue)
        .overlay(alignment: .top) {
            if let error = blocks.loadError ?? lists.loadError {
                Text(error).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("saved-data-error")
            } else if recovery.isChecking {
                ProgressView("Checking saved blocks…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("foreground-recovery")
                    .allowsHitTesting(false)
            }
        }
        #if DEBUG
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["BLOCK_TAB"], let tab = Int(raw) {
                selection = tab == 1 ? 1 : 0
            }
        }
        #endif
    }
}

#Preview { ContentView() }
