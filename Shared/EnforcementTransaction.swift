import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Serializes app/extension transitions, including their shield and monitor writes.
/// An actor or NSLock alone cannot protect the other process. The recursive local
/// mutex also prevents threads sharing one process from sharing a flock lease.
/// No async suspension is permitted while a lease is held.
enum EnforcementTransaction {
    private static let mutex = NSRecursiveLock()
    private static var depth = 0
    private static var descriptor: Int32 = -1
    private static var lockURL: URL? {
        #if os(iOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedDefaults.appGroupID)?
            .appendingPathComponent("enforcement.lock")
        #else
        // Command-line regression harnesses explicitly supply a shared test path.
        return URL(fileURLWithPath: ProcessInfo.processInfo.environment["TYRI_TRANSACTION_PATH"]
            ?? NSTemporaryDirectory() + "tyri-enforcement-tests-\(ProcessInfo.processInfo.processIdentifier).lock")
        #endif
    }

    final class Lease {
        private var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            depth -= 1
            if depth == 0 {
                // UserDefaults is a cache, not a transaction. Flush while holding
                // the interprocess lease before the next reader can acquire it.
                SharedDefaults.suite.synchronize()
                flock(descriptor, LOCK_UN)
                close(descriptor)
                descriptor = -1
            }
            mutex.unlock()
        }
    }

    /// Failure leaves enforcement unchanged. Never fall back to an unlocked write.
    static func begin(wait: Bool = true) -> Lease? {
        if wait { mutex.lock() }
        else if !mutex.try() { return nil }
        if depth == 0 {
            guard let url = lockURL else { mutex.unlock(); return nil }
            let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { mutex.unlock(); return nil }
            var result: Int32
            repeat { result = flock(fd, wait ? LOCK_EX : LOCK_EX | LOCK_NB) } while result != 0 && errno == EINTR
            guard result == 0 else { close(fd); mutex.unlock(); return nil }
            descriptor = fd
            SharedDefaults.suite.synchronize()
        }
        depth += 1
        return Lease()
    }
}
