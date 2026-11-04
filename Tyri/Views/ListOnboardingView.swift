import SwiftUI

struct ListStarter: Identifiable {
    let name: String
    let icon: String
    let detail: String
    let examples: String
    var id: String { name }
    static let suggestions = [
        ListStarter(name: "Social media", icon: "person.2", detail: "Make room away from social updates.", examples: "Consider Instagram, Facebook, Snapchat, Threads, or X—whichever pull you away."),
        ListStarter(name: "Games", icon: "gamecontroller", detail: "Keep playtime intentional.", examples: "Choose the games you find hardest to put down. You can also select the Games category in the picker."),
        ListStarter(name: "Scrollers", icon: "hand.draw", detail: "Take a break from endless feeds and videos.", examples: "Consider TikTok, Reddit, YouTube, or Instagram. An app can belong to more than one list.")
    ]
}

struct ListOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groups = AppGroupStore.shared
    @State private var draft: AppGroup?
    @State private var recommendation: String?
    var onFinish: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(.tint)
                        Text("What pulls you away?").font(.title2.bold())
                        Text("Build a few lists now. Later, describe when you want to block them.").foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }.listRowBackground(Color.clear)
                Section("Start with a suggestion") {
                    ForEach(ListStarter.suggestions) { starter in
                        Button {
                            recommendation = starter.examples
                            draft = groups.groups.first { $0.name.caseInsensitiveCompare(starter.name) == .orderedSame }
                                ?? AppGroup(name: starter.name)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(starter.name).font(.headline).foregroundStyle(.primary)
                                    Text(starter.detail).font(.subheadline).foregroundStyle(.secondary)
                                    Text(groups.groups.contains { $0.name.caseInsensitiveCompare(starter.name) == .orderedSame } ? "Review your list" : "Choose apps").font(.caption)
                                }
                            } icon: { Image(systemName: starter.icon) }
                            .padding(.vertical, 6)
                        }.accessibilityIdentifier("starter-\(starter.name)")
                    }
                }
                Section {
                    Button {
                        recommendation = nil
                        draft = AppGroup(name: "")
                    } label: { Label("Make your own list", systemImage: "plus") }
                } footer: {
                    Text("Suggestions are a starting point. You choose the apps, can rename any list, and can put the same app in multiple lists. Creating a list doesn't start blocking.")
                }
                if !groups.groups.isEmpty {
                    Section("Your lists") {
                        ForEach(groups.groups) { group in
                            Label(group.name, systemImage: "checkmark.circle").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Build your lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip for now") { finish() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { finish() } }
            }
            .sheet(item: $draft) { group in
                NavigationStack {
                    AppGroupEditorView(groupID: group.id, newGroup: groups.group(id: group.id) == nil ? group : nil,
                                       recommendation: recommendation, requireContents: true)
                }
            }
        }
    }
    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }
}
