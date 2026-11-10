import Foundation

@main struct Tests {
    static func main() throws {
        let namespace = "usage.\(UUID())"
        var ledger = MonitorLedger(legacyName: namespace, context: "A")
        let first = ledger.reserve(namespace: namespace, context: "A")
        precondition(ledger.confirmed?.name == namespace, "Reservation must preserve the accepted allowance")
        precondition(ledger.acceptCallback(namespace, context: "A") == .alreadyAccepted)
        precondition(ledger.acceptCallback(first.name, context: "A") == .promoted)
        precondition(ledger.complete(first, context: nil, succeeded: false) == .alreadyAccepted,
                     "Late failure cannot undo an early callback's accepted owner")
        precondition(ledger.confirmed == first && ledger.pending == nil)
        let b = ledger.reserve(namespace: namespace, context: "B")
        let aAgain = ledger.reserve(namespace: namespace, context: "A")
        precondition(aAgain.name != first.name && aAgain.name != b.name, "ABA must not reuse a name")
        precondition(ledger.complete(b, context: "B", succeeded: true) == .obsolete)
        precondition(ledger.complete(aAgain, context: "A", succeeded: true) == .promoted)
        precondition(ledger.retired.contains(first.name) && !ledger.retired.contains(aAgain.name))
        ledger.discoverOrphans([first.name, aAgain.name], namespace: namespace)
        precondition(ledger.retired.contains(first.name) && !ledger.retired.contains(aAgain.name))
        let restored = try JSONDecoder().decode(MonitorLedger.self, from: JSONEncoder().encode(ledger))
        precondition(restored == ledger, "Crash/restart preserves all ownership and retirement state")
        let stale = ledger.reserve(namespace: namespace, context: "A")
        precondition(ledger.complete(stale, context: "changed", succeeded: true) == .obsolete)
        precondition(ledger.confirmed == aAgain && ledger.pending == nil)
        let failed = ledger.reserve(namespace: namespace, context: "A")
        precondition(ledger.complete(failed, context: "A", succeeded: false) == .failed)
        precondition(ledger.confirmed == aAgain, "Failure must retain confirmed allowance")
        ledger.invalidate()
        precondition(ledger.acceptCallback(aAgain.name, context: "A") == .obsolete)
        precondition(ledger.confirmed == nil && ledger.pending == nil)
        ledger.retired.remove(first.name)
        ledger.discoverOrphans([first.name], namespace: namespace)
        precondition(ledger.retired.contains(first.name), "A very late start remains an orphan after cleanup")
        let scheduleNamespace = "block.\(UUID())"
        var legacy = MonitorLedger(legacyName: scheduleNamespace, context: "overnight")
        legacy.discoverOrphans([scheduleNamespace + ".early", scheduleNamespace + ".late"], namespace: scheduleNamespace)
        precondition(legacy.retired.isEmpty, "Upgrade retired live legacy segments before replacement confirmation")
        let replacement = legacy.reserve(namespace: scheduleNamespace, context: "overnight")
        precondition(legacy.complete(replacement, context: "overnight", succeeded: true) == .promoted)
        legacy.discoverOrphans([scheduleNamespace + ".early", scheduleNamespace + ".late"], namespace: scheduleNamespace)
        precondition(legacy.retired.contains(scheduleNamespace + ".early") && legacy.retired.contains(scheduleNamespace + ".late"))
        print("PASS: durable ownership, old/early callbacks, late failure, ABA, stale completion, restart and orphan cleanup")
    }
}
