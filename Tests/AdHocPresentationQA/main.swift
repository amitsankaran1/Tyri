import Foundation
import Combine

struct AppGroup {}
@MainActor final class ForegroundRecovery {
    static let shared = ForegroundRecovery()
    func request() { AdHocMonitoring.reconcile() }
}
struct AdHocSession: Equatable {
    var id = UUID()
    var endsAt = Date().addingTimeInterval(600)
    var releaseAt: Date?
}
enum SharedDefaults {
    static let suite = UserDefaults(suiteName: "tyri-adhoc-presentation-\(UUID())")!
    enum Keys {
        static func shieldError(blockID: UUID) -> String { "shield.\(blockID)" }
        static func usageLockError(blockID: UUID) -> String { "lock.\(blockID)" }
    }
}
enum AdHocMonitoring {
    static var session: AdHocSession?
    static var reconciliations = 0
    static func reconcile() {
        reconciliations += 1
        if let item = session, item.endsAt <= Date() { session = nil }
    }
    static func start(group: AppGroup, minutes: Int) throws { session = AdHocSession() }
    static func requestRelease() throws { session?.releaseAt = Date().addingTimeInterval(300) }
    static func release() { session = nil }
}
@MainActor final class ScreenTimeManager {
    enum Authorization { case approved, denied }
    static let shared = ScreenTimeManager()
    var authorizationStatus: Authorization = .approved
}
@MainActor final class AppGroupStore {
    static let shared = AppGroupStore()
    func flush() {}
}

@main struct Tests {
    @MainActor static func main() throws {
        let manager = AdHocManager.shared
        var changes = 0
        let observation = manager.objectWillChange.sink { changes += 1 }
        defer { withExtendedLifetime(observation) {} }
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        for _ in 0..<10 { manager.refresh(reconcile: false) }
        check(changes == 0, "Unchanged empty-session polls must not invalidate an open setup menu")
        check(AdHocMonitoring.reconciliations == 0, "Presentation polling must preserve reconciliation policy")

        AdHocMonitoring.session = AdHocSession()
        manager.refresh(reconcile: false)
        check(manager.session == AdHocMonitoring.session && changes > 0, "A newly active session must appear")
        var before = changes
        for _ in 0..<10 { manager.refresh(reconcile: false) }
        check(changes == before, "Unchanged active-session polls must not rebuild presentation")
        try manager.requestRelease()
        check(manager.session?.releaseAt != nil && changes > before, "Release-wait changes must remain observable")

        let id = manager.session!.id
        before = changes
        SharedDefaults.suite.set("Shield failure", forKey: SharedDefaults.Keys.shieldError(blockID: id))
        manager.refresh(reconcile: false)
        check(manager.enforcementError == "Shield failure" && changes > before, "Error-only changes must remain observable")
        before = changes
        manager.refresh(reconcile: false)
        check(changes == before, "An unchanged error must not republish")
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.shieldError(blockID: id))
        SharedDefaults.suite.set("Monitor failure", forKey: SharedDefaults.Keys.usageLockError(blockID: id))
        manager.refresh(reconcile: false)
        check(manager.enforcementError == "Monitor failure", "Monitor recovery errors must still appear")
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: id))
        before = changes
        manager.refresh(reconcile: false)
        check(manager.enforcementError == nil && changes > before, "Cleared errors must refresh presentation")

        AdHocMonitoring.session?.endsAt = Date().addingTimeInterval(-1)
        manager.refresh(reconcile: false)
        check(manager.session == nil && AdHocMonitoring.reconciliations > 0, "Expired-session polling must still reconcile and clear")
        before = AdHocMonitoring.reconciliations
        manager.refresh()
        check(AdHocMonitoring.reconciliations == before + 1, "Explicit refresh must still reconcile")
        print("PASS: \(checks) production temporary-session presentation checks with OS doubles")
    }
}
