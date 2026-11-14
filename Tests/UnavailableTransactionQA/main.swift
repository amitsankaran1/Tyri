import Foundation

enum SharedDefaults {
    static let name = ProcessInfo.processInfo.environment["TYRI_TEST_SUITE"]!
    static let suite = UserDefaults(suiteName: name)!
}

@main struct UnavailableTransactionQA {
    static func main() throws {
        defer { SharedDefaults.suite.removePersistentDomain(forName: SharedDefaults.name) }
        let mode = CommandLine.arguments[1]
        if mode == "unavailable" {
            precondition(EnforcementTransaction.beginEffect() == nil,
                         "unavailable shared storage must fail closed")
            // The failed acquisition must release its mutex and admission lock;
            // a repaired storage location can be retried without relaunching.
            let path = ProcessInfo.processInfo.environment["TYRI_TRANSACTION_PATH"]!
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            guard let lease = EnforcementTransaction.beginEffect() else { fatalError("retry after storage repair") }
            lease.finish()
            print("PASS: unavailable storage returns; repaired storage retries")
        } else if mode == "disabled" {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                EnforcementTransaction.setEffectsEnabled(false)
            }
            precondition(EnforcementTransaction.beginEffect() == nil,
                         "background expiration must stop a contended effect")
            print("PASS: disabled admission interrupts contention")
        } else {
            guard let lease = EnforcementTransaction.beginEffect() else { fatalError("contention must retry") }
            SharedDefaults.suite.set(true, forKey: "acquired")
            lease.finish()
            print("PASS: real cross-process lock contention retries successfully")
        }
    }
}
