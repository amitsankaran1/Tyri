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

    @Published private(set) var loadError: String?

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
        guard loadError == nil else { return }
        guard !groups.contains(where: { $0.id == item.id }) else { return }
        groups.append(item)
        flush()
    }

    func update(_ group: AppGroup) {
        guard loadError == nil else { return }
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        var stamped = group
        stamped.updatedAt = Date()
        groups[idx] = stamped
        save()
    }

    func setSelection(id: UUID, selection: FamilyActivitySelection) {
        guard loadError == nil else { return }
        guard var g = group(id: id) else { return }
        g.selection = selection
        update(g)
    }

    func delete(id: UUID) {
        guard loadError == nil else { return }
        groups.removeAll(where: { $0.id == id })
        save()
    }

    /// How many blocks reference this group — surfaced in the UI before deletion.
    func blockCount(for groupID: UUID, in blocks: [BlockRule]) -> Int {
        blocks.filter { $0.appGroupIDs.contains(groupID) }.count
    }

    func replaceAll(_ newGroups: [AppGroup]) {
        guard loadError == nil else { return }
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
        guard loadError == nil else { return }
        do {
            let data = try JSONEncoder().encode(groups)
            defaults.set(data, forKey: groupsKey)
        } catch {
            print("❌ Failed to encode groups: \(error)")
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: groupsKey) else { groups = []; loadError = nil; return }
        do {
            groups = try JSONDecoder().decode([AppGroup].self, from: data)
            loadError = nil
        } catch {
            print("❌ Failed to decode groups: \(error)")
            loadError = "Saved lists could not be read. Your original data has been kept. Open Settings for diagnostics or Emergency Access. Update Tyri if this data came from a newer version."
        }
    }
}
