//
//  BlockEditorView.swift
//  Tyri
//
//  Create/edit a block: choose its type, the app lists it targets, and the
//  type-specific config (schedule / usage limit / tag), plus cooldown friction.
//

import SwiftUI
import FamilyControls

struct BlockEditorView: View {
    let blockID: UUID
    var newBlock: BlockRule? = nil
    var onFinish: (() -> Void)? = nil

    @StateObject private var blockStore = BlockStore.shared
    @StateObject private var groupStore = AppGroupStore.shared
    @StateObject private var schedulingManager = SchedulingManager.shared
    @StateObject private var usageLimitManager = UsageLimitManager.shared
    @StateObject private var screenTimeManager = ScreenTimeManager.shared
    @StateObject private var breakManager = BreakManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var validationError: String?
    @State private var name = ""
    @State private var type: BlockType = .schedule
    @State private var groupIDs: Set<UUID> = []
    @State private var schedule: BlockingSchedule?
    @State private var cooldownMinutes = 5
    @State private var breakMinutes = 0
    @State private var usageLimitMinutes = 30
    @State private var usageLockMinutes = 180
    @State private var isEnabled = false

    @State private var showCooldown = false
    @State private var showBreak = false
    @State private var showDeleteConfirm = false
    @State private var showActiveDeleteAlert = false
    @State private var hasLoaded = false

    static let cooldownOptions: [Int] = [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    static let breakOptions: [Int] = [0, 5, 10, 15, 20, 30]

    var body: some View {
        Form {
            if let block = storedBlock {
                Section {
                    let presentation = BlockStatusPresentation.current(for: block)
                    BlockStatusCard(status: presentation)
                    if let start = presentation.lockStart, let end = presentation.lockEnd {
                        LockElapsedView(start: start, end: end)
                    }
                    if presentation.state == .tracking, let limit = presentation.limitMinutes {
                        UsageProgressView(used: presentation.usedMinutes, limit: limit)
                    }
                }.listRowBackground(Color.clear)
            }
            if isActive {
                Section {
                    breakActionRow
                    if storedCooldownMinutes == 0 {
                        Label(noCooldownExplainer, systemImage: "lock.fill")
                            .font(.system(.caption, design: .default))
                            .foregroundColor(Color.secondary)
                    } else {
                        Button { showCooldown = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "hourglass")
                                Text("Stop early…")
                            }
                            .foregroundColor(Color.orange)
                        }
                    }
                }
            }

            if let block = storedBlock, let error = schedulingManager.registrationErrors[block.id] {
                Section { ScheduleRegistrationWarning(block: block, message: error) }
            }
            if isActive {
                Section {
                    Label("This block is active. You can rename it or add lists, but you can't weaken it while it runs.", systemImage: "lock.fill")
                        .font(.system(.caption, design: .default))
                        .foregroundColor(Color.secondary)
                }
            }

            Section("Name") {
                TextField("Block name", text: $name).textInputAutocapitalization(.words)
            }

            Section("How it applies") {
                Picker("Type", selection: $type) {
                    Text("Schedule").tag(BlockType.schedule)
                    Text("Usage limit").tag(BlockType.timer)
                    Text("NFC tag").tag(BlockType.tag)
                }
                .disabled(isActive)
                .opacity(isActive ? 0.5 : 1)
                Text(typeBlurb)
                    .font(.system(.caption, design: .default))
                    .foregroundColor(Color.secondary)
            }

            Section("App lists") {
                if groupStore.groups.isEmpty {
                    Text("No lists yet — create one in the Lists tab first.")
                        .font(.system(.caption, design: .default))
                        .foregroundColor(Color.secondary)
                } else {
                    ForEach(groupStore.groups) { group in
                        // Adding lists strengthens an active block and stays allowed;
                        // unchecking a stored list would weaken it, so those rows lock.
                        let locked = isActive && storedGroupIDs.contains(group.id)

                        Toggle(group.name, isOn: Binding(
                            get: { groupIDs.contains(group.id) },
                            set: { selected in
                                if selected { groupIDs.insert(group.id) } else { groupIDs.remove(group.id) }
                            }
                        ))
                        .disabled(locked)

                    }
                }
            }

            typeConfigSection
            flexibilitySection

            if !isActive {
                Section("Manual") {
                    Toggle("Block now", isOn: $isEnabled).tint(Color.accentColor)
                    Text("Starts when you tap Save. This manual block stays on beyond any schedule or usage timer. Your Stop early setting applies.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if isEnabled && cooldownMinutes == 0 {
                        Text("With Stop early set to Not allowed, this manual block has no automatic end.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }


            Section {
                Button("Save block", action: save)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("save-block")
            }

            if newBlock == nil {
                Section {
                    Button(role: .destructive) {
                        if isActive { showActiveDeleteAlert = true } else { showDeleteConfirm = true }
                    } label: {
                        HStack(spacing: 10) { Image(systemName: "trash"); Text("Delete Block") }
                    }
                }
            }
        }
        .alert("Couldn’t start blocking", isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })) {
            Button("OK", role: .cancel) { validationError = nil }
        } message: {
            Text(validationError ?? "")
        }
        .navigationTitle(newBlock == nil ? "Block details" : "New block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || groupIDs.isEmpty) }
        }
        .sheet(isPresented: $showCooldown) {
            CooldownView(blockID: blockID, isPresented: $showCooldown)
        }
        .sheet(isPresented: $showBreak) {
            BreakView(blockID: blockID, isPresented: $showBreak)
        }
        .onChange(of: showCooldown) { showing in
            // A release inside the sheet flips the stored isEnabled off; re-sync so
            // a Save right after doesn't re-apply the shield.
            if !showing { isEnabled = storedBlock?.isEnabled ?? false }
        }
        .alert("Couldn't start break", isPresented: Binding(
            get: { breakManager.lastError != nil },
            set: { if !$0 { breakManager.lastError = nil } }
        )) { Button("OK", role: .cancel) { breakManager.lastError = nil } }
        message: { Text(breakManager.lastError ?? "") }
        .alert("Delete block?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteBlock() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Block is active", isPresented: $showActiveDeleteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(storedCooldownMinutes == 0
                 ? "This block can't be deleted while it's active, and it's set to “Stop early: Not allowed” — wait for it to end first."
                 : "Disable the block first (its cooldown applies), then delete it.")
        }
        .onAppear {
            loadIfNeeded()
            // Close the periodic-refresh staleness window so `isActive` is current.
            schedulingManager.refresh()
            usageLimitManager.refresh()
        }
    }

    // MARK: - Type-specific config

    @ViewBuilder
    private var typeConfigSection: some View {
        switch type {
        case .schedule:
            Section("Schedule") {
                NavigationLink {
                    ScheduleEditorView(schedule: $schedule)
                } label: {
                    HStack {
                        Image(systemName: "clock").foregroundColor(Color.accentColor)
                        Text(schedule?.summary ?? "Set schedule").foregroundColor(Color.primary)
                    }
                }
                .accessibilityIdentifier("edit-schedule")
                .disabled(isActive)
                .opacity(isActive ? 0.5 : 1)
            }
        case .timer:
            Section("Usage limit") {
                UsageDurationPicker(title: "Allow usage for", minutes: $usageLimitMinutes).disabled(isActive)
                UsageDurationPicker(title: "Then block for", minutes: $usageLockMinutes).disabled(isActive)
                Text("Use apps for \(Self.minutesLabel(usageLimitMinutes)), then block them for \(Self.minutesLabel(usageLockMinutes)). Repeat after each block ends.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Unused time resets at midnight.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .tag:
            Section("Tag") {
                Text("Tapping your registered tag toggles this block on or off, together with your other Tag blocks.")
                    .font(.system(.caption, design: .default))
                    .foregroundColor(Color.secondary)
            }
        }
    }


    private var flexibilitySection: some View {
        Section {
            Picker("Stop early", selection: $cooldownMinutes) {
                ForEach(Self.cooldownOptions, id: \.self) { minutes in
                    Text(minutes == 0 ? "Not allowed" : "Wait \(Self.minutesLabel(minutes))").tag(minutes)
                }
            }
            .disabled(isActive)
            Text(cooldownMinutes == 0
                 ? (type == .tag ? "Use your NFC tag to stop blocking. You can't stop it early here."
                    : "Apps stay blocked until this block ends. You can't stop it early here.")
                 : "To stop blocking early, first wait \(Self.minutesLabel(cooldownMinutes)). Your apps stay blocked while you wait.")
                .font(.footnote).foregroundStyle(.secondary)
            if type != .timer {
                Picker("Take a break", selection: $breakMinutes) {
                    ForEach(Self.breakOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? "Not allowed" : "\(Self.minutesLabel(minutes))").tag(minutes)
                    }
                }
                .disabled(isActive)
                Text(breakMinutes == 0
                     ? "No temporary pauses during this block."
                     : "Pause this block once for \(Self.minutesLabel(breakMinutes)) each \(type == .tag ? "tag session" : "scheduled session"). Blocking resumes automatically. Other active blocks still apply.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("When you need access")
        } footer: {
            Text("These choices can't be changed while the block is active.")
        }
    }

    /// "Take a break" affordance while the block is active. Timer blocks never
    /// offer breaks; their lockout already auto-expires.
    @ViewBuilder
    private var breakActionRow: some View {
        if let block = storedBlock, block.type != .timer, block.breakMinutes > 0 {
            if breakManager.isOnBreak(blockID: blockID) {
                Button { showBreak = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("On break — view countdown")
                    }
                    .foregroundColor(Color.green)
                }
            } else if breakManager.isBreakAvailable(for: block) {
                Button { showBreak = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer")
                        Text("Take a break (\(block.breakMinutes) min)")
                    }
                    .foregroundColor(Color.accentColor)
                }
            } else if BreakMonitoring.breakUsed(blockID: blockID) {
                Label("Break already used — the next \(block.type == .tag ? "tag session" : "window") gets a fresh one.",
                      systemImage: "cup.and.saucer")
                    .font(.system(.caption, design: .default))
                    .foregroundColor(Color.secondary)
            }
            // (No row while another block's break is running — one break at a time.)
        }
    }


    private var typeBlurb: String {
        switch type {
        case .schedule: return "Blocks the selected lists during a time-of-day window."
        case .timer:    return "Use your apps, take a forced pause, then start fresh. Time used across these lists counts toward one limit."
        case .tag:      return "Blocks the lists while toggled on by tapping your NFC tag."
        }
    }

    private var storedBlock: BlockRule? { blockStore.block(id: blockID) }

    /// Active per the shared SSOT (manual/tag enable, scheduled run, or usage
    /// lock) — always judged from the *stored* block, not in-editor state.
    private var isActive: Bool {
        storedBlock.map { screenTimeManager.isBlockActive($0) } ?? false
    }

    private var storedGroupIDs: Set<UUID> { Set(storedBlock?.appGroupIDs ?? []) }

    private var storedCooldownMinutes: Int { storedBlock?.cooldownMinutes ?? 5 }

    private var noCooldownExplainer: String {
        storedBlock?.type == .tag
            ? "This block is set to “Stop early: Not allowed” — it can't be turned off here. Tap your tag to toggle it off."
            : "This block is set to “Stop early: Not allowed” — it can't be turned off until its schedule window or lockout ends."
    }

    nonisolated static func minutesLabel(_ m: Int) -> String {
        m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60) hr \(m % 60) min")
    }
    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    // MARK: - Load / save

    private func loadIfNeeded() {
        guard !hasLoaded, let block = blockStore.block(id: blockID) ?? newBlock else { return }
        name = block.name
        type = block.type
        groupIDs = Set(block.appGroupIDs)
        schedule = block.schedule ?? (newBlock != nil && block.type == .schedule ? BlockingSchedule() : nil)
        cooldownMinutes = Self.cooldownOptions.min(by: { abs($0 - block.cooldownMinutes) < abs($1 - block.cooldownMinutes) }) ?? block.cooldownMinutes
        breakMinutes = Self.breakOptions.min(by: { abs($0 - block.breakMinutes) < abs($1 - block.breakMinutes) }) ?? block.breakMinutes
        if let l = block.usageLimitMinutes {
            usageLimitMinutes = l
        }
        usageLockMinutes = block.usageLockMinutes
        isEnabled = block.isEnabled
        hasLoaded = true
    }

    private func save() {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard hasLoaded, var block = blockStore.block(id: blockID) ?? newBlock else { finish(); return }

        screenTimeManager.checkAuthorizationStatus()
        guard !isEnabled || screenTimeManager.authorizationStatus == .approved else {
            validationError = "Allow Screen Time access in Settings before using Block now."
            return
        }
        validationError = nil

        // Defense-in-depth: while the block is active, only strengthening edits
        // survive, even if the UI locks were somehow bypassed (stale state, a
        // block going active while the editor was open, ...).
        let wasActive = screenTimeManager.isBlockActive(block)
        if wasActive {
            type = block.type
            schedule = block.schedule
            if let limit = block.usageLimitMinutes { usageLimitMinutes = limit }
            usageLockMinutes = block.usageLockMinutes
            cooldownMinutes = block.cooldownMinutes
            breakMinutes = block.breakMinutes
            groupIDs.formUnion(block.appGroupIDs)
            isEnabled = block.isEnabled || isEnabled
        }

        let prevType = block.type
        let prevSchedule = block.schedule
        let prevLimit = block.usageLimitMinutes
        let prevLock = block.usageLockMinutes
        let prevGroupIDs = Set(block.appGroupIDs)

        block.name = name.isEmpty ? "Untitled" : name
        block.type = type
        block.appGroupIDs = Array(groupIDs)
        block.cooldownMinutes = cooldownMinutes
        block.breakMinutes = (type == .timer) ? 0 : breakMinutes
        block.isEnabled = isEnabled
        block.schedule = (type == .schedule) ? schedule : nil
        block.usageLimitMinutes = (type == .timer) ? usageLimitMinutes : nil
        block.usageLockMinutes = usageLockMinutes
        let targets = BlockResolution.tokens(for: block, groups: groupStore.groups)
        guard !isEnabled || !targets.isEmpty || !targets.domains.isEmpty else {
            validationError = "Choose apps or websites in this block's lists before using Block now."
            return
        }
        if blockStore.block(id: blockID) == nil { blockStore.insert(block) }
        else { blockStore.update(block) }
        blockStore.flush()

        // Manual on/off + live-shield refresh.
        if isEnabled {
            // A fresh manual activation re-arms the one-break allowance.
            if !wasActive { BreakMonitoring.resetAllowance(blockID: block.id) }
            screenTimeManager.applyBlockShield(block)
        } else {
            // Only clear if nothing else is keeping it up.
            let running = SharedDefaults.suite.bool(forKey: SharedDefaults.Keys.running(blockID: blockID))
            let locked = usageLimitManager.lockEnd(for: blockID) != nil
            if !running && !locked { screenTimeManager.clearBlockShield(id: blockID) }
            else { screenTimeManager.updateBlockShieldIfActive(block) }
        }

        // (Re)register monitors for the (possibly changed) type. Skip when nothing
        // the monitor depends on changed and the block is mid-run: applySchedule
        // tears down first (clearing the running flag mid-window), so a no-op Save
        // on an active block must not re-register — that was a two-Save bypass.
        if prevType == .schedule && type != .schedule {
            schedulingManager.removeSchedule(for: block)
        }
        if prevType == .timer && type != .timer {
            usageLimitManager.removeUsageLimit(for: block)
        }
        let scheduleChanged = prevType != type || prevSchedule != block.schedule
        let limitsChanged = prevType != type
            || prevLimit != block.usageLimitMinutes
            || prevLock != block.usageLockMinutes
            || prevGroupIDs != Set(block.appGroupIDs)
        switch type {
        case .schedule:
            if scheduleChanged || !wasActive || schedulingManager.registrationErrors[block.id] != nil {
                schedulingManager.applySchedule(for: block)
            }
        case .timer:    usageLimitManager.applyUsageLimit(for: block, forceReset: limitsChanged)
        case .tag:      break
        }

        if schedulingManager.registrationErrors[block.id] == nil { finish() }
    }

    private func deleteBlock() {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard let block = blockStore.block(id: blockID) else {
            blockStore.delete(id: blockID)
            finish()
            return
        }
        // Backstop for the UI gate: never tear down an active block.
        guard !screenTimeManager.isBlockActive(block) else {
            showActiveDeleteAlert = true
            return
        }
        blockStore.delete(id: blockID)
        blockStore.flush()
        schedulingManager.removeSchedule(for: block)
        usageLimitManager.removeUsageLimit(for: block)
        screenTimeManager.clearBlockShield(id: blockID)
        finish()
    }
}
