import SwiftUI
import FamilyControls

struct AppGroupListView: View {
    @StateObject private var groups = AppGroupStore.shared
    @StateObject private var blocks = BlockStore.shared
    @State private var selectedID: UUID?
    @State private var newGroup: AppGroup?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                if groups.groups.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Choose your distractions").font(.headline)
                            Text("Group apps and websites into a list, then use it in any block.")
                                .foregroundStyle(.secondary)
                            Button { newGroup = AppGroup(name: "") } label: {
                                Label("Create a list", systemImage: "plus")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        ForEach(groups.groups) { group in
                            NavigationLink(value: group.id) {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.name).font(.headline)
                                        Text(summary(group)).font(.subheadline).foregroundStyle(.secondary)
                                        if !group.selection.categoryTokens.isEmpty {
                                            Text("Includes whole categories").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: "square.grid.2x2").foregroundStyle(.tint)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } footer: {
                        Text("Lists can be reused by more than one block.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { newGroup = AppGroup(name: "") } label: { Label("Add list", systemImage: "plus") }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            if let selectedID, groups.group(id: selectedID) != nil {
                NavigationStack {
                    AppGroupEditorView(groupID: selectedID, onFinish: { self.selectedID = nil })
                        .id(selectedID)
                }
            } else {
                SelectionPlaceholder(title: "Your lists, your rules", systemImage: "square.grid.2x2",
                                     description: "Choose a list to edit its apps and websites.")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $newGroup) { group in
            NavigationStack { AppGroupEditorView(groupID: group.id, newGroup: group) }
        }
        .onChange(of: groups.groups.map(\.id)) { ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
    }

    private func summary(_ group: AppGroup) -> String {
        var parts: [String] = []
        let apps = group.selection.applicationTokens.count
        let websites = group.blockedWebDomains.count + group.selection.webDomainTokens.count
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if websites > 0 { parts.append("\(websites) website\(websites == 1 ? "" : "s")") }
        if parts.isEmpty { parts.append(group.selection.categoryTokens.isEmpty ? "No apps yet" : "Whole categories") }
        let count = groups.blockCount(for: group.id, in: blocks.blocks)
        parts.append("\(count) block\(count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}
