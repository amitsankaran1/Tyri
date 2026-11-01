//
//  BlockStore.swift
//  Tyri
//
//  Persists `[BlockRule]` to the App Group suite. Host-only.
//  (Formerly PresetStore; blocks reference AppGroups instead of embedding apps.)
//

import Foundation
import Combine

@MainActor
class BlockStore: ObservableObject {
    static let shared = BlockStore()

    @Published private(set) var blocks: [BlockRule] = []

    private let blocksKey = SharedDefaults.Keys.blocks
    private var defaults: UserDefaults { SharedDefaults.suite }
    private var saveTask: Task<Void, Never>?

    private init() {
        load()
    }

    // MARK: - Public API

    func block(id: UUID) -> BlockRule? {
        blocks.first(where: { $0.id == id })
    }

    func blocks(ofType type: BlockType) -> [BlockRule] {
        blocks.filter { $0.type == type }
    }

    @discardableResult
    func create(name: String, type: BlockType = .schedule) -> BlockRule {
        let block = BlockRule(name: name, type: type)
        blocks.append(block)
        save()
        return block
    }

    func insert(_ item: BlockRule) {
        guard !blocks.contains(where: { $0.id == item.id }) else { return }
        blocks.append(item)
        flush()
    }

    func update(_ block: BlockRule) {
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        if blocks[idx].isEnabled != block.isEnabled {
            defaults.set(UUID().uuidString, forKey: SharedDefaults.Keys.manualActivation(blockID: block.id))
            defaults.removeObject(forKey: SharedDefaults.Keys.cooldownEnd(blockID: block.id))
            defaults.removeObject(forKey: SharedDefaults.Keys.cooldownActivation(blockID: block.id))
        }
        blocks[idx] = block
        save()
    }

    func delete(id: UUID) {
        blocks.removeAll(where: { $0.id == id })
        save()
        defaults.removeObject(forKey: SharedDefaults.Keys.running(blockID: id))
        defaults.removeObject(forKey: SharedDefaults.Keys.cooldownEnd(blockID: id))
        defaults.removeObject(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id))
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard var b = block(id: id) else { return }
        b.isEnabled = enabled
        update(b)
    }

    /// Replace the whole set (used by migration). Persists synchronously.
    func replaceAll(_ newBlocks: [BlockRule]) {
        blocks = newBlocks
        flush()
    }

    // MARK: - Persistence

    private func save() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            if !Task.isCancelled { self.persistNow() }
        }
    }

    /// Cancel pending debounced save and flush to disk synchronously, so the
    /// extension and other cross-process readers see fresh state immediately.
    func flush() {
        saveTask?.cancel()
        persistNow()
    }

    func reload() { load() }

    private func persistNow() {
        do {
            let data = try JSONEncoder().encode(blocks)
            defaults.set(data, forKey: blocksKey)
        } catch {
            print("❌ Failed to encode blocks: \(error)")
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: blocksKey) else { blocks = []; return }
        do {
            blocks = try JSONDecoder().decode([BlockRule].self, from: data)
        } catch {
            print("❌ Failed to decode blocks: \(error)")
            blocks = []
        }
    }
}
