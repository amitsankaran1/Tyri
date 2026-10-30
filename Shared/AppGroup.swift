//
//  AppGroup.swift
//  Tyri
//
//  A named, reusable list of apps (e.g. "Social media", "Games"). Blocks
//  reference groups by id; a block's effective shield is the union of its
//  groups' selections (see BlockResolution).
//
//  Add target membership to BOTH Tyri and TyriMonitor targets.
//

import Foundation
import FamilyControls

struct AppGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var selection: FamilyActivitySelection
    /// Typed-in website domains to block (e.g. "goodreads.com"), enforced via
    /// `webContent.blockedByFilter` — no picker token needed.
    var blockedWebDomains: [String]
    var createdAt: Date
    /// Last time the list was saved. Surfaced on the Lists page so the snapshot
    /// nature of category selections (see AppGroupEditorView) reads as intentional
    /// rather than stale — a whole-category pick captures the apps installed at
    /// save time, not future ones.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        selection: FamilyActivitySelection = FamilyActivitySelection(),
        blockedWebDomains: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.selection = selection
        self.blockedWebDomains = blockedWebDomains
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func == (lhs: AppGroup, rhs: AppGroup) -> Bool {
        let scalarsEqual = lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
            && lhs.blockedWebDomains == rhs.blockedWebDomains
        let appsEqual: Bool = lhs.selection.applicationTokens == rhs.selection.applicationTokens
        let catsEqual: Bool = lhs.selection.categoryTokens == rhs.selection.categoryTokens
        let webEqual: Bool = lhs.selection.webDomainTokens == rhs.selection.webDomainTokens
        return scalarsEqual && appsEqual && catsEqual && webEqual
    }

    /// Encoding routes `selection` through nested `Data` to insulate from changes
    /// in `FamilyActivitySelection`'s codable representation (mirrors BlockRule).
    enum CodingKeys: String, CodingKey {
        case id, name, selectionData, blockedWebDomains, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        blockedWebDomains = try c.decodeIfPresent([String].self, forKey: .blockedWebDomains) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        // Back-compat: lists saved before this field existed show their creation
        // date until the next save stamps a real value.
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        if let data = try c.decodeIfPresent(Data.self, forKey: .selectionData) {
            selection = (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)) ?? FamilyActivitySelection()
        } else {
            selection = FamilyActivitySelection()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(blockedWebDomains, forKey: .blockedWebDomains)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        let selectionData = try JSONEncoder().encode(selection)
        try c.encode(selectionData, forKey: .selectionData)
    }
}

extension FamilyActivitySelection {
    /// A copy carrying the same tokens but with `includeEntireCategory: true`.
    /// `includeEntireCategory` is init-only (`let`), so the flag can't be flipped
    /// in place — but the three token sets are settable. Used to re-pin the flag
    /// when loading a stored selection into the picker (including old selections
    /// saved under `false`), so editing keeps app-level granularity.
    func includingEntireCategory() -> FamilyActivitySelection {
        var copy = FamilyActivitySelection(includeEntireCategory: true)
        copy.applicationTokens = applicationTokens
        copy.categoryTokens = categoryTokens
        copy.webDomainTokens = webDomainTokens
        return copy
    }

    /// True when `self` contains every token of `other` (an adds-only change).
    /// `includeEntireCategory` is deliberately ignored — BlockResolution unions
    /// exactly these three token sets.
    func isSuperset(of other: FamilyActivitySelection) -> Bool {
        applicationTokens.isSuperset(of: other.applicationTokens)
            && categoryTokens.isSuperset(of: other.categoryTokens)
            && webDomainTokens.isSuperset(of: other.webDomainTokens)
    }
}
