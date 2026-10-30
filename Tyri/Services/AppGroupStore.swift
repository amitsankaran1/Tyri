//
//  AppGroupStore.swift
//  Tyri
//
//  Persists `[AppGroup]` (reusable app lists) to the App Group suite. Host-only.
//

import Foundation
import FamilyControls
import Combine

@MainActor
class AppGroupStore: ObservableObject {
    static let shared = AppGroupStore()

    @Published private(set) var groups: [AppGroup] = []

    private let groupsKey = SharedDefaults.Keys.groups
    private var defaults: UserDefaults { SharedDefaults.suite }
    private var saveTask: Task<Void, Never>?

    private init() {
        load()
    }

    // MARK: - Public API

    func group(id: UUID) -> AppGroup? {
        groups.first(where: { $0.id == id })
    }

    func groups(ids: [UUID]) -> [AppGroup] {
        groups.filter { ids.contains($0.id) }
    }

    @discardableResult
    func create(name: String) -> AppGroup {
        let group = AppGroup(name: name)
        groups.append(group)
        save()
        return group
    }

    func insert(_ item: AppGroup) {
        guard !groups.contains(where: { $0.id == item.id }) else { return }
        groups.append(item)
        flush()
    }

    func update(_ group: AppGroup) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        var stamped = group
        stamped.updatedAt = Date()
        groups[idx] = stamped
        save()
    }

    func setSelection(id: UUID, selection: FamilyActivitySelection) {
        guard var g = group(id: id) else { return }
        g.selection = selection
        update(g)
    }

    func delete(id: UUID) {
        groups.removeAll(where: { $0.id == id })
        save()
    }

    /// How many blocks reference this group — surfaced in the UI before deletion.
    func blockCount(for groupID: UUID, in blocks: [BlockRule]) -> Int {
        blocks.filter { $0.appGroupIDs.contains(groupID) }.count
    }

    func replaceAll(_ newGroups: [AppGroup]) {
        groups = newGroups
        flush()
    }

    // MARK: - Persistence

    private func save() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { self.persistNow() }
        }
    }

    func flush() {
        saveTask?.cancel()
        persistNow()
    }

    func reload() { load() }

    private func persistNow() {
        do {
            let data = try JSONEncoder().encode(groups)
            defaults.set(data, forKey: groupsKey)
        } catch {
            print("❌ Failed to encode groups: \(error)")
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: groupsKey) else { groups = []; return }
        do {
            groups = try JSONDecoder().decode([AppGroup].self, from: data)
        } catch {
            print("❌ Failed to decode groups: \(error)")
            groups = []
        }
    }
}
