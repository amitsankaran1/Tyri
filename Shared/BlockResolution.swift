//
//  BlockResolution.swift
//  Tyri
//
//  Resolves a BlockRule to the enforcement tokens it should shield: the union of
//  its referenced AppGroups' tokens. Shared by the app and the TyriMonitor
//  extension so both compute identical shields (mirrors BlockingActuator).
//
//  We union the readable token Sets directly (rather than reconstruct a
//  FamilyActivitySelection) and feed them straight to ManagedSettingsStore
//  shields and DeviceActivityEvent — both take token sets.
//
//  Add target membership to BOTH Tyri and TyriMonitor targets.
//

import Foundation
import FamilyControls
import ManagedSettings

enum BlockResolution {

    struct Tokens {
        var apps: Set<ApplicationToken>
        var categories: Set<ActivityCategoryToken>
        var webDomains: Set<WebDomainToken>
        /// Typed-in website domains (strings), enforced via `webContent.blockedByFilter`.
        var domains: Set<String>

        /// Token-only emptiness — deliberately excludes `domains`: the sole caller
        /// gates `DeviceActivityEvent` creation, and usage counting can only watch
        /// tokens, never typed-in domains.
        var isEmpty: Bool { apps.isEmpty && categories.isEmpty && webDomains.isEmpty }
    }

    /// Union of the selections of the groups a block references.
    static func tokens(for block: BlockRule, groups: [AppGroup]) -> Tokens {
        var apps: Set<ApplicationToken> = []
        var categories: Set<ActivityCategoryToken> = []
        var webDomains: Set<WebDomainToken> = []
        var domains: Set<String> = []
        let referenced = block.appGroupIDs
        for group in groups where referenced.contains(group.id) {
            apps.formUnion(group.selection.applicationTokens)
            categories.formUnion(group.selection.categoryTokens)
            webDomains.formUnion(group.selection.webDomainTokens)
            domains.formUnion(group.blockedWebDomains)
        }
        return Tokens(apps: apps, categories: categories, webDomains: webDomains, domains: domains)
    }

    // MARK: - Shared-store loaders (used by app + extension)

    static func loadGroups() -> [AppGroup] {
        guard let data = SharedDefaults.suite.data(forKey: SharedDefaults.Keys.groups) else { return [] }
        return (try? JSONDecoder().decode([AppGroup].self, from: data)) ?? []
    }

    static func loadBlocks() -> [BlockRule] {
        guard let data = SharedDefaults.suite.data(forKey: SharedDefaults.Keys.blocks) else { return [] }
        return (try? JSONDecoder().decode([BlockRule].self, from: data)) ?? []
    }

    static func loadBlock(id: UUID) -> BlockRule? {
        loadBlocks().first(where: { $0.id == id })
    }

    /// Tokens for a block id, resolved against the persisted groups.
    static func tokens(forBlockID id: UUID) -> Tokens? {
        guard let block = loadBlock(id: id) else { return nil }
        return tokens(for: block, groups: loadGroups())
    }
}
