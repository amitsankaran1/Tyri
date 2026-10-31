import SwiftUI
import FamilyControls

/// One navigation tree adapts in place. Never replace the editor when size classes change.
struct HomeView: View {
    var openLists: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var blockStore = BlockStore.shared
    @StateObject private var groupStore = AppGroupStore.shared
    @StateObject private var screenTime = ScreenTimeManager.shared
    @StateObject private var nfc = NFCManager.shared
    @StateObject private var config = AppConfigurationStore.shared
    @StateObject private var scheduling = SchedulingManager.shared
    @StateObject private var usage = UsageLimitManager.shared
    @StateObject private var breaks = BreakManager.shared
    @State private var selectedID: UUID?
    @State private var newBlock: BlockRule?
    @State private var showSettings = false

    private var authorized: Bool { screenTime.authorizationStatus == .approved }
    private var active: [BlockRule] {
        blockStore.blocks.filter { screenTime.isBlockActive($0) && !breaks.isOnBreak(blockID: $0.id) }
    }
    private var onBreak: [BlockRule] {
        blockStore.blocks.filter { breaks.isOnBreak(blockID: $0.id) }
    }
    private var configured: [BlockRule] {
        blockStore.blocks.filter { !screenTime.isBlockActive($0) && !breaks.isOnBreak(blockID: $0.id) }
    }
    private var tagIsOn: Bool { blockStore.blocks(ofType: .tag).contains { $0.isEnabled } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(authorized ? (active.isEmpty ? "No active blocks" : "Blocking is on") : "Let's get set up",
                              systemImage: authorized && !active.isEmpty ? "lock.shield.fill" : "lock.shield")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Text(statusDescription).font(.subheadline).foregroundStyle(.secondary)
                        if !blockStore.blocks(ofType: .tag).isEmpty && config.isTagRegistered {
                            if nfc.isScanning {
                                ProgressView("Hold iPhone near your tag")
                                Button("Cancel scan") { nfc.stopScanning() }
                            } else {
                                Button { nfc.startScanning() } label: {
                                    Label(tagIsOn ? "Stop tag blocks" : "Start tag blocks",
                                          systemImage: "sensor.tag.radiowaves.forward")
                                        .frame(maxWidth: .infinity)
                                }
                                .primaryActionButton()
                                .disabled(!authorized)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if !authorized || groupStore.groups.isEmpty || blockStore.blocks.isEmpty {
                    Section("Get started") {
                        if !authorized {
                            Button { showSettings = true } label: {
                                Label("Allow Screen Time access", systemImage: "hand.raised")
                            }
                        }
                        if groupStore.groups.isEmpty {
                            Button(action: openLists) {
                                Label("Choose apps to block", systemImage: "square.grid.2x2")
                            }
                        }
                        if blockStore.blocks.isEmpty {
                            Button { newBlock = BlockRule(name: "", type: .schedule) } label: {
                                Label("Create your first block", systemImage: "plus")
                            }
                        }
                    }
                }
                if !blockStore.blocks(ofType: .tag).isEmpty && !config.isTagRegistered {
                    Section {
                        Button { showSettings = true } label: {
                            Label("Connect your NFC tag", systemImage: "sensor.tag.radiowaves.forward")
                        }
                    }
                }
                blockSection(authorized ? "Blocking now" : "Configured as active", blocks: active)
                blockSection("On break", blocks: onBreak)
                blockSection("Your blocks", blocks: configured)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Focus")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach([BlockType.schedule, .timer, .tag], id: \.self) { type in
                            Button { newBlock = BlockRule(name: "", type: type) } label: {
                                Label(BlockTypeStyle.title(type), systemImage: BlockTypeStyle.icon(type))
                            }
                        }
                    } label: { Label("Add block", systemImage: "plus") }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            if let selectedID, blockStore.block(id: selectedID) != nil {
                NavigationStack {
                    BlockEditorView(blockID: selectedID, onFinish: { self.selectedID = nil })
                        .id(selectedID)
                }
            } else {
                SelectionPlaceholder(title: "Make room for focus", systemImage: "lock.shield",
                                     description: "Choose a block to view its settings, or add a new one.")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sheet(item: $newBlock) { block in
            NavigationStack {
                BlockEditorView(blockID: block.id, newBlock: block)
            }
        }
        .alert("Couldn't scan tag", isPresented: Binding(
            get: { nfc.errorMessage != nil },
            set: { if !$0 { nfc.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { nfc.errorMessage = nil }
        } message: { Text(nfc.errorMessage ?? "Please try again.") }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { phase in if phase == .active { refresh() } }
        .onChange(of: blockStore.blocks.map(\.id)) { ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
    }

    @ViewBuilder
    private func blockSection(_ title: String, blocks: [BlockRule]) -> some View {
        if !blocks.isEmpty {
            Section(title) {
                ForEach(blocks) { block in
                    NavigationLink(value: block.id) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(block.name).font(.headline)
                                Text(summary(block)).font(.subheadline).foregroundStyle(.secondary)
                                if breaks.isOnBreak(blockID: block.id), let end = BreakMonitoring.breakEnd(blockID: block.id) {
                                    Text(end, style: .timer).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                } else if block.type == .timer, let end = usage.lockEnd(for: block.id) {
                                    Text("Locked until \(end.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: breaks.isOnBreak(blockID: block.id) ? "cup.and.saucer" : BlockTypeStyle.icon(block.type))
                                .foregroundStyle(.tint)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var statusDescription: String {
        if !authorized { return "Allow Screen Time access to start blocking distractions." }
        if !onBreak.isEmpty && active.isEmpty { return "You're on a break. Blocking will resume automatically." }
        if active.isEmpty { return "Your apps are available. Start a tag block or let your schedules take over." }
        return "\(active.count) block\(active.count == 1 ? " is" : "s are") helping you focus."
    }
    private func summary(_ block: BlockRule) -> String {
        switch block.type {
        case .schedule: return block.schedule?.summary ?? "No schedule set"
        case .timer: return "\(BlockEditorView.minutesLabel(block.usageLimitMinutes ?? 30)) daily limit"
        case .tag: return tagIsOn && block.isEnabled ? "On until you scan your tag" : "Start with your NFC tag"
        }
    }
    private func refresh() {
        screenTime.checkAuthorizationStatus()
        scheduling.refresh()
        usage.reconcileExpiredLocks()
    }
}
