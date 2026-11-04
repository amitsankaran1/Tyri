import SwiftUI

struct ContentView: View {
    var storesReady = false
    @State private var selection = 0
    @State private var showOnboarding = false
    @AppStorage("listOnboardingSeen.v1") private var onboardingSeen = false

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
        .onChange(of: storesReady) { ready in
            guard ready, !onboardingSeen else { return }
            onboardingSeen = true
            #if DEBUG
            if ProcessInfo.processInfo.environment["BLOCK_RUN_TEST_HARNESS"] == "1" && ProcessInfo.processInfo.environment["TYRI_TEST_ONBOARDING"] != "1" { return }
            #endif
            showOnboarding = AppGroupStore.shared.groups.isEmpty && BlockStore.shared.blocks.isEmpty
        }
        .sheet(isPresented: $showOnboarding) { ListOnboardingView(onFinish: { showOnboarding = false }) }
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
