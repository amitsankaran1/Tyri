import Foundation

/// Pure durable ownership state. Callers persist each transition while holding
/// EnforcementTransaction, then perform native IPC after releasing that lease.
/// Names are never reused, even when configuration changes A -> B -> A.
nonisolated struct MonitorLedger: Codable, Equatable {
    struct Owner: Codable, Equatable, Sendable {
        let name: String
        let context: String
    }
    enum Completion: Equatable { case promoted, alreadyAccepted, failed, obsolete }
    var schema = 1
    var confirmed: Owner?
    var pending: Owner?
    var retired: Set<String> = []

    init(legacyName: String?, context: String) {
        confirmed = legacyName.map { Owner(name: $0, context: context) }
    }

    mutating func reserve(namespace: String, context: String) -> Owner {
        if let pending { retired.insert(pending.name) }
        if let confirmed, confirmed.context != context {
            retired.insert(confirmed.name)
            self.confirmed = nil
        }
        let owner = Owner(name: namespace + ".r-" + UUID().uuidString, context: context)
        pending = owner
        return owner
    }

    /// A callback can confirm a pending registration before startMonitoring
    /// returns. A later success, failure or cancellation must respect that fact.
    mutating func complete(_ owner: Owner, context: String?, succeeded: Bool) -> Completion {
        if confirmed == owner { return .alreadyAccepted }
        guard pending == owner else { return .obsolete }
        guard context == owner.context else {
            pending = nil
            retired.insert(owner.name)
            return .obsolete
        }
        guard succeeded else {
            pending = nil
            retired.insert(owner.name)
            return .failed
        }
        if let confirmed { retired.insert(confirmed.name) }
        confirmed = owner
        pending = nil
        return .promoted
    }

    mutating func acceptCallback(_ name: String, context: String?) -> Completion {
        guard let context else { return .obsolete }
        if let confirmed, confirmed.name == name, confirmed.context == context { return .alreadyAccepted }
        guard let pending, pending.name == name else { return .obsolete }
        return complete(pending, context: context, succeeded: true)
    }

    mutating func invalidate() {
        if let confirmed { retired.insert(confirmed.name) }
        if let pending { retired.insert(pending.name) }
        confirmed = nil
        pending = nil
    }

    func owns(_ name: String) -> Bool {
        if confirmed?.name == name || pending?.name == name { return true }
        if let confirmed, confirmed.name.hasPrefix("block."), !confirmed.name.contains(".r-") {
            return name == confirmed.name + ".early" || name == confirmed.name + ".late"
        }
        return false
    }

    /// Discover a late native completion even after an earlier cleanup observed
    /// it absent. Removing a retired receipt cannot make a name eligible again.
    mutating func discoverOrphans(_ observed: Set<String>, namespace: String) {
        for name in observed where (name == namespace || name.hasPrefix(namespace + ".")) && !owns(name) {
            retired.insert(name)
        }
    }
}
