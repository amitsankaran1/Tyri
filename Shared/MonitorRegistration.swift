import Foundation

nonisolated struct MonitorReservation: Sendable {
    let namespace: String
    let owner: MonitorLedger.Owner
    var name: String { owner.name }
}

/// Mutations require EnforcementTransaction; render-time snapshot reads do not.
/// Native IPC is not part of this store. The old confirmed owner survives a
/// provisional registration with unchanged semantic inputs.
enum MonitorRegistration {
    static let prefix = "monitorRegistration.v1."
    static func key(_ namespace: String) -> String { prefix + namespace }

    static func load(_ namespace: String, legacyName: String?, context: String) -> MonitorLedger? {
        guard let data = SharedDefaults.suite.data(forKey: key(namespace)) else {
            return MonitorLedger(legacyName: legacyName, context: context)
        }
        guard let value = try? JSONDecoder().decode(MonitorLedger.self, from: data), value.schema == 1 else { return nil }
        return value
    }

    private static func save(_ ledger: MonitorLedger, namespace: String) {
        if let data = try? JSONEncoder().encode(ledger) { SharedDefaults.suite.set(data, forKey: key(namespace)) }
    }

    static func reserve(_ namespace: String, legacyName: String?, context: String) -> MonitorReservation? {
        guard var ledger = load(namespace, legacyName: legacyName, context: context) else { return nil }
        let owner = ledger.reserve(namespace: namespace, context: context)
        save(ledger, namespace: namespace)
        return MonitorReservation(namespace: namespace, owner: owner)
    }

    static func finish(_ ticket: MonitorReservation, context: String?, succeeded: Bool) -> MonitorLedger.Completion {
        guard var ledger = load(ticket.namespace, legacyName: nil, context: "") else { return .obsolete }
        let result = ledger.complete(ticket.owner, context: context, succeeded: succeeded)
        save(ledger, namespace: ticket.namespace)
        return result
    }

    static func accept(_ name: String, namespace: String, legacyName: String?, context: String?) -> MonitorLedger.Completion {
        guard let context, var ledger = load(namespace, legacyName: legacyName, context: context) else { return .obsolete }
        let result = ledger.acceptCallback(name, context: context)
        save(ledger, namespace: namespace)
        return result
    }

    static func current(_ namespace: String, legacyName: String) -> String {
        load(namespace, legacyName: legacyName, context: "")?.confirmed?.name ?? namespace + ".inactive"
    }

    static func pending(_ namespace: String) -> MonitorReservation? {
        guard let owner = load(namespace, legacyName: nil, context: "")?.pending else { return nil }
        return MonitorReservation(namespace: namespace, owner: owner)
    }

    static func invalidate(_ namespace: String, legacyName: String?) {
        guard var ledger = load(namespace, legacyName: legacyName, context: "") else { return }
        ledger.invalidate()
        save(ledger, namespace: namespace)
    }

    static func retirementNames(observed: Set<String>) -> Set<String> {
        var names: Set<String> = []
        for key in SharedDefaults.suite.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let namespace = String(key.dropFirst(prefix.count))
            guard var ledger = load(namespace, legacyName: nil, context: "") else { continue }
            ledger.discoverOrphans(observed, namespace: namespace)
            save(ledger, namespace: namespace)
            names.formUnion(ledger.retired.filter { !ledger.owns($0) })
        }
        return names
    }

    static func isRetired(_ name: String) -> Bool {
        for key in SharedDefaults.suite.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let namespace = String(key.dropFirst(prefix.count))
            if let ledger = load(namespace, legacyName: nil, context: ""), ledger.retired.contains(name), !ledger.owns(name) { return true }
        }
        return false
    }

    static func acknowledgeRetired(_ names: Set<String>) {
        for key in SharedDefaults.suite.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let namespace = String(key.dropFirst(prefix.count))
            guard var ledger = load(namespace, legacyName: nil, context: "") else { continue }
            ledger.retired.subtract(names.filter { !ledger.owns($0) })
            save(ledger, namespace: namespace)
        }
    }
}
