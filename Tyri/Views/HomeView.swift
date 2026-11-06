import SwiftUI
import Combine
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
    @State private var showAdHoc = false
    @StateObject private var adHoc = AdHocManager.shared

    @StateObject private var cooldown = CooldownManager.shared
    @State private var refreshDate = Date()
    private let statusTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private var authorized: Bool { BlockStatusPresentation.canDisplayActivity }
    private func status(_ block: BlockRule) -> BlockStatusPresentation {
        _ = refreshDate
        return .current(for: block)
    }
    private func blocks(in state: BlockStatusPresentation.State) -> [BlockRule] {
        blockStore.blocks.filter { status($0).state == state }
    }
    private var active: [BlockRule] { blocks(in: .blocking) }
    private var tracking: [BlockRule] { blocks(in: .tracking) }
    private var onBreak: [BlockRule] { blocks(in: .paused) }
    private var configured: [BlockRule] {
        blockStore.blocks.filter { [.off, .setup, .unavailable].contains(status($0).state) }
    }
    private var tagIsOn: Bool { blockStore.blocks(ofType: .tag).contains { $0.isEnabled } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        BlockStatusCard(status: overview)
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
                ForEach(blockStore.blocks.filter { scheduling.registrationErrors[$0.id] != nil }) { block in
                    Section {
                        ScheduleRegistrationWarning(block: block, message: scheduling.registrationErrors[block.id] ?? "")
                    }
                }
                Section {
                    Button { showAdHoc = true } label: {
                        Label(adHoc.session.map { "\($0.group.name) · Unblocks at \($0.endsAt.formatted(date: .omitted, time: .shortened))" } ?? "Block for a while", systemImage: "timer")
                    }
                    .accessibilityIdentifier("ad-hoc-block")
                }
                ForEach(blockStore.blocks.filter { usageError($0.id) != nil }) { block in
                    Section {
                        Label(usageError(block.id) ?? "", systemImage: "exclamationmark.triangle")
                        Button("Retry block") { usage.applyUsageLimit(for: block); usage.reconcileExpiredLocks(); refreshDate = Date() }
                    } header: { Text(block.name) }
                }
                blockSection("Blocking now", blocks: active)
                blockSection("Tracking usage", blocks: tracking)
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
        .sheet(isPresented: $showAdHoc) { NavigationStack { AdHocBlockView() } }
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
        .onReceive(statusTimer) { now in
            guard scenePhase == .active else { return }
            refreshDate = now
            usage.refresh()
            adHoc.refresh()
        }
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
                                let presentation = status(block)
                                Label(presentation.title, systemImage: "circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(presentation.color)
                                Text(presentation.detail).font(.caption).foregroundStyle(.secondary)
                                if let start = presentation.lockStart, let end = presentation.lockEnd {
                                    LockElapsedView(start: start, end: end)
                                }
                                if presentation.state == .tracking, let limit = presentation.limitMinutes {
                                    UsageProgressView(used: presentation.usedMinutes, limit: limit)
                                        .padding(.top, 4)
                                }
                            }
                        } icon: {
                            Image(systemName: breaks.isOnBreak(blockID: block.id) ? "cup.and.saucer" : BlockTypeStyle.icon(block.type))
                                .foregroundStyle(status(block).color)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("open-block-\(block.name)")
                }
            }
        }
    }

    private var overview: BlockStatusPresentation {
        if !authorized {
            return .init(state: .setup, detail: "Allow Screen Time access to start blocking distractions.")
        }
        if let session = adHoc.session {
            return .init(state: .blocking, detail: "\(session.group.name) · Unblocks at \(session.endsAt.formatted(date: .omitted, time: .shortened)). Other active blocks still apply.")
        }
        if let first = active.first {
            let names = active.count == 1 ? first.name : "\(first.name) +\(active.count - 1) more"
            let detail = active.count == 1 ? "\(names) · \(status(first).detail)" : "\(names). Each block stays on until its own end time."
            return .init(state: .blocking, detail: detail)
        }
        if let first = onBreak.first {
            return .init(state: .paused, detail: "\(first.name) is paused. Blocking resumes automatically.", end: status(first).end)
        }
        if !tracking.isEmpty {
            return .init(state: .tracking, detail: "Your usage limit\(tracking.count == 1 ? " is" : "s are") running. Apps stay available until you reach a limit.")
        }
        if configured.contains(where: { status($0).state == .unavailable }) {
            return .init(state: .unavailable, detail: "A block needs attention. Open it to check its lists, permission or schedule.")
        }
        return .init(state: .off, detail: "No blocks are on right now. Your scheduled and tag blocks are ready when you need them.")
    }
    private func summary(_ block: BlockRule) -> String {
        switch block.type {
        case .schedule: return block.schedule?.summary ?? "No schedule set"
        case .timer: return "Use \(BlockEditorView.minutesLabel(block.usageLimitMinutes ?? 30)), then block for \(BlockEditorView.minutesLabel(block.usageLockMinutes))"
        case .tag: return tagIsOn && block.isEnabled ? "On until you scan your tag" : "Start with your NFC tag"
        }
    }
    private func usageError(_ id: UUID) -> String? {
        SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageLockError(blockID: id))
            ?? SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageError(blockID: id))
    }
    private func refresh() {
        breaks.restoreActiveBreaksIfAny()
        adHoc.refresh()
        screenTime.checkAuthorizationStatus()
        screenTime.restoreBlockingIfNeeded()
        usage.reconcileExpiredLocks()
        if screenTime.authorizationStatus == .approved {
            scheduling.repairMissingSchedules()
            usage.reapplyAllUsageLimits()
        }
    }
}
