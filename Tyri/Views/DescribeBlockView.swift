import SwiftUI

struct DescribeBlockView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groups = AppGroupStore.shared
    @State private var text = ""
    @State private var result: BlockDescriptionDraft?
    @State private var error: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var missingDraft: AppGroup?
    @State private var missingIndex: Int?
    @State private var review: BlockRule?
    @State private var saved = false
    @State private var showDiscard = false
    private let examples = ["Block Social media and Games weekdays from 9am to 5pm", "Allow 40 minutes on Scrollers, then block for 50 minutes", "Block Games when I scan my NFC tag"]

    var body: some View {
        Form {
            if DescriptionService.isFixture {
                Section { Label("Development fixture · no model request", systemImage: "hammer") }
            }
            Section {
                Text("Which lists, and when?").font(.title2.bold())
                Text("Describe one block. You'll review the lists, timing, and access settings before saving.").foregroundStyle(.secondary)
                TextEditor(text: $text).frame(minHeight: 110).accessibilityIdentifier("block-description")
                    .onChange(of: text) { _ in result = nil; error = nil }
                    .disabled(busy)
            }
            if let error {
                Section("Needs your attention") { Text(error).foregroundStyle(.secondary) }
            }
            if let result {
                if missingReferences(result).isEmpty {
                    Section { Button("Review block") { makeReview(result) }.accessibilityIdentifier("review-described-block") }
                } else {
                    Section {
                        ForEach(missingReferences(result), id: \.self) { index in
                            Button("Create \(result.lists[index].name)") {
                                missingIndex = index
                                missingDraft = AppGroup(name: result.lists[index].name)
                            }
                        }
                    } header: { Text("Create missing lists") } footer: {
                        Text("Choose apps for these lists, then return here. Your block description stays in place. Each list is saved when you confirm it; the block is saved separately after review.")
                    }
                }
            }
            Section {
                if busy {
                    HStack { ProgressView(); Text("Interpreting your block…") }
                    Button("Cancel request") { task?.cancel() }
                } else {
                    Button("Interpret description") { interpret() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
                        .accessibilityIdentifier("interpret-description")
                }
            } footer: {
                Text("Your description and list names are sent to Tyri's model service. App selections stay on your device. Weekly schedules, repeating usage limits, and NFC blocks are supported.")
            }
            Section("Try a description") {
                ForEach(examples, id: \.self) { example in Button(example) { text = example }.disabled(busy) }
            }
            Section("Your lists") {
                if groups.groups.isEmpty { Text("No lists yet. You can create a missing list after describing your block.").foregroundStyle(.secondary) }
                ForEach(groups.groups) { group in Text(group.name) }
            }
        }
        .navigationTitle("Describe a block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
            if text.isEmpty { dismiss() } else { showDiscard = true }
        } } }
        .interactiveDismissDisabled(!text.isEmpty)
        .confirmationDialog("Discard this block description?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard description", role: .destructive) { task?.cancel(); dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
        .sheet(item: $missingDraft, onDismiss: { missingIndex = nil }) { group in
            NavigationStack {
                AppGroupEditorView(groupID: group.id, newGroup: group, onFinish: {
                    if groups.group(id: group.id) != nil, let index = missingIndex {
                        result?.lists[index].existingID = group.id.uuidString
                    }
                    missingDraft = nil
                }, recommendation: "Choose apps to finish this list. The name is a suggestion—you can edit it before saving.", requireContents: true)
            }
        }
        .sheet(item: $review, onDismiss: { if saved { dismiss() } }) { block in
            NavigationStack {
                BlockEditorView(blockID: block.id, newBlock: block, onFinish: { review = nil },
                                sourceDescription: text, onSaved: { saved = true })
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func missingReferences(_ draft: BlockDescriptionDraft) -> [Int] {
        draft.lists.indices.filter { i in
            guard let raw = draft.lists[i].existingID, let id = UUID(uuidString: raw) else { return true }
            return groups.group(id: id) == nil
        }
    }
    private func interpret() {
        task?.cancel(); busy = true; error = nil; result = nil
        let request = DescriptionRequest(text: text, lists: groups.groups.map { .init(id: $0.id.uuidString, name: $0.name) },
                                         timeZone: TimeZone.current.identifier, locale: Locale.current.identifier)
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let draft = try await DescriptionService.shared.interpret(request)
                try Task.checkCancellation()
                try draft.validate()
                let known = Set(request.lists.map { $0.id.lowercased() })
                guard draft.lists.allSatisfy({ $0.existingID == nil || known.contains($0.existingID!.lowercased()) }) else { throw DescriptionError.invalid }
                result = draft
            } catch is CancellationError { } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    private func makeReview(_ draft: BlockDescriptionDraft) {
        do {
            try draft.validate()
            guard missingReferences(draft).isEmpty, let type = BlockType(rawValue: draft.type ?? "") else { throw DescriptionError.invalid }
            let ids = draft.lists.compactMap { UUID(uuidString: $0.existingID ?? "") }
            var block = BlockRule(name: draft.name, type: type, appGroupIDs: Array(Set(ids)),
                                  cooldownMinutes: draft.cooldownMinutes ?? 5, breakMinutes: draft.breakMinutes ?? 0,
                                  usageLimitMinutes: draft.usageMinutes, usageLockMinutes: draft.lockoutMinutes ?? 180)
            if let weekly = draft.schedule {
                block.schedule = BlockingSchedule(startHour: weekly.startMinute / 60, startMinute: weekly.startMinute % 60,
                                                  endHour: weekly.endMinute / 60, endMinute: weekly.endMinute % 60, weekdays: Set(weekly.weekdays))
            }
            review = block
        } catch { self.error = error.localizedDescription }
    }
}
