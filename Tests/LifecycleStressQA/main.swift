import Foundation

struct RNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

@main struct LifecycleStressQA {
    // Operation values, not generated UUIDs, identify the replay. Minimization
    // removes operations while retaining the same violated invariant.
    static func minimize(_ input: [UInt64], fails: ([UInt64]) -> Bool) -> [UInt64] {
        var trace = input
        var size = max(1, trace.count / 2)
        while size > 0 {
            var i = 0
            while i + size <= trace.count {
                var candidate = trace
                candidate.removeSubrange(i..<(i + size))
                if fails(candidate) { trace = candidate } else { i += size }
            }
            size /= 2
        }
        return trace
    }

    static func ledger(_ operations: [UInt64]) -> String? {
        let namespace = "usage.fixture"
        var ledger = MonitorLedger(legacyName: namespace, context: "A")
        var tickets: [MonitorLedger.Owner] = []
        var allNames: Set<String> = [namespace]
        for value in operations {
            let context = ["A", "B", "C"][Int((value >> 8) % 3)]
            let old = ledger
            switch value % 7 {
            case 0, 1:
                let ticket = ledger.reserve(namespace: namespace, context: context)
                if allNames.contains(ticket.name) { return "reservation reused identity" }
                allNames.insert(ticket.name); tickets.append(ticket)
                if old.confirmed?.context == context && ledger.confirmed != old.confirmed {
                    return "same-input reservation reset healthy confirmed owner"
                }
            case 2:
                guard !tickets.isEmpty else { continue }
                let ticket = tickets[Int((value >> 16) % UInt64(tickets.count))]
                let success = value & 0x80 != 0
                _ = ledger.complete(ticket, context: context, succeeded: success)
                if old.confirmed != ticket && old.pending != ticket && ledger != old {
                    return "stale native completion changed newer ownership"
                }
                if !success && old.pending == ticket && old.confirmed != ticket && ledger.confirmed != old.confirmed {
                    return "native failure replaced confirmed owner"
                }
            case 3:
                guard !tickets.isEmpty else { continue }
                let ticket = tickets[Int((value >> 16) % UInt64(tickets.count))]
                _ = ledger.acceptCallback(ticket.name, context: context)
                if old.confirmed?.name != ticket.name && old.pending?.name != ticket.name && ledger != old {
                    return "stale callback changed newer ownership"
                }
            case 4:
                ledger.invalidate()
                if ledger.confirmed != nil || ledger.pending != nil { return "cancellation retained live owner" }
            case 5:
                guard let bytes = try? JSONEncoder().encode(ledger),
                      let restored = try? JSONDecoder().decode(MonitorLedger.self, from: bytes), restored == ledger else {
                    return "restart lost durable ownership"
                }
                ledger = restored
            default:
                ledger.discoverOrphans(allNames, namespace: namespace)
                if ledger.confirmed != old.confirmed || ledger.pending != old.pending {
                    return "orphan observation replaced live ownership"
                }
                for name in allNames where !ledger.owns(name) {
                    if !ledger.retired.contains(name) { return "late native completion escaped retirement" }
                }
                ledger.retired.removeAll() // simulate completed native cleanup
            }
            if let confirmed = ledger.confirmed, ledger.retired.contains(confirmed.name) {
                return "confirmed monitor retired"
            }
            if let pending = ledger.pending, ledger.retired.contains(pending.name) {
                return "pending monitor retired"
            }
        }
        return nil
    }

    static func main() {
        let env = ProcessInfo.processInfo.environment
        let seeds: [UInt64] = env["QA_SEED"].flatMap(UInt64.init).map { [$0] } ?? Array(1...64)
        let steps = env["QA_STEPS"].flatMap(Int.init) ?? 1000
        let replay = env["QA_TRACE"].flatMap { try? JSONDecoder().decode([UInt64].self, from: Data($0.utf8)) }
        precondition(steps > 0, "QA_STEPS must be positive")
        for seed in replay == nil ? seeds : [0] {
            var rng = RNG(state: seed)
            let operations = replay ?? (0..<steps).map { _ in rng.next() }
            for (label, run) in [("ownership", ledger)] {
                if let failure = run(operations) {
                    let minimal = minimize(operations) { run($0) == failure }
                    print("FAIL: \(label): \(failure); QA_SEED=\(seed) QA_STEPS=\(steps)")
                    print("Replay minimized: QA_TRACE='\(minimal)' python3 Tests/LifecycleStressQA/run.py")
                    exit(1)
                }
            }
        }
        let count = replay.map { $0.count } ?? seeds.count * steps
        print("PASS: \(count) production ownership operations; persistence, stale completion/callback rejection and retained confirmed owners")
        print("Pure production MonitorLedger transitions. This does not establish actual Screen Time counting or shielding.")
    }
}
