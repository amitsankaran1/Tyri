import Foundation

@main struct UnavailableActuatorQA {
    static func main() {
        defer { SharedDefaults.suite.removePersistentDomain(forName: SharedDefaults.name) }
        let path = ProcessInfo.processInfo.environment["TYRI_TRANSACTION_PATH"]!
        let id = UUID()
        BlockResolution.known.insert(id)
        let lease = EnforcementTransaction.begin()!
        BlockingActuator.apply(tokens: .init(apps: [1]), blockID: id)
        let effects = lease.finish(deferEffects: true)
        // Lose shared-storage access between durable intent and native effects.
        setenv("TYRI_TRANSACTION_PATH", path + "/missing/lock", 1)
        for effect in effects { effect() }
        precondition(NativeProbe.writes == 0, "unavailable storage must not bypass the lease")
        setenv("TYRI_TRANSACTION_PATH", path, 1)
        BlockingActuator.replayPending()
        precondition(NativeProbe.writes > 0, "pending intent must survive and replay after repair")
        precondition(NativeProbe.lockedCalls == 0, "native IPC must remain outside the lease")
        print("PASS: actuator unavailable storage returns without native writes; durable intent replays after repair")
    }
}
