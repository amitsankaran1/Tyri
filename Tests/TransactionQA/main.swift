import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
enum SharedDefaults { static let suite = UserDefaults(suiteName: ProcessInfo.processInfo.environment["TYRI_TEST_SUITE"]!)! }
@main struct TransactionQA {
 static func main() {
  let command=CommandLine.arguments[1]
  if command == "worker" {
   for _ in 0..<40 {
    guard let outer=EnforcementTransaction.begin() else {fatalError("outer lease")}
    guard let inner=EnforcementTransaction.begin() else {fatalError("recursive lease")}
    let count=SharedDefaults.suite.integer(forKey:"counter")
    usleep(500)
    SharedDefaults.suite.set(count+1,forKey:"counter")
    inner.finish();outer.finish()
   }
  } else if command == "crash" {
   guard let lease=EnforcementTransaction.begin() else {fatalError("lease")}
   SharedDefaults.suite.set(true,forKey:"crashEntered");SharedDefaults.suite.synchronize()
   _ = lease
   _exit(0) // intentionally omit finish; the kernel must release the descriptor.
  } else {
   guard let lease=EnforcementTransaction.begin() else {fatalError("lease after crash")}
   print("Observed counter: \(SharedDefaults.suite.integer(forKey:"counter"))")
   precondition(SharedDefaults.suite.integer(forKey:"counter")==320,"lost cross-process update")
   precondition(SharedDefaults.suite.bool(forKey:"crashEntered"),"crash fixture didn't run")
   lease.finish()
   print("PASS: 8 processes × 40 nested transitions; 320/320 updates retained; process exit releases lease")
  }
 }
}
