import Foundation
import Combine
import FamilyControls

@MainActor
final class AdHocManager: ObservableObject {
    static let shared = AdHocManager()
    @Published private(set) var session: AdHocSession?
    @Published private(set) var enforcementError: String?
    private init() {
        session = AdHocMonitoring.session
        enforcementError = Self.error(for: session)
    }
    private static func error(for session: AdHocSession?) -> String? {
        guard let session else { return nil }
        return SharedDefaults.suite.string(forKey: SharedDefaults.Keys.shieldError(blockID: session.id))
            ?? SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageLockError(blockID: session.id))
    }
    func refresh(reconcile: Bool = true) {
        if reconcile || (AdHocMonitoring.session.map { $0.endsAt <= Date() } ?? false) { ForegroundRecovery.shared.request() }
        publishPersistedState()
    }
    func publishPersistedState() {
        let latest = AdHocMonitoring.session
        let latestError = Self.error(for: latest)
        // Publishing an unchanged value rebuilds an open SwiftUI picker menu.
        // Keep real session and error changes observable without timer churn.
        if session != latest { session = latest }
        if enforcementError != latestError { enforcementError = latestError }
    }
    func start(group: AppGroup, minutes: Int) throws {
        guard ScreenTimeManager.shared.authorizationStatus == .approved else {
            throw NSError(domain: "Tyri", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow Screen Time access in Settings first."])
        }
        AppGroupStore.shared.flush()
        try AdHocMonitoring.start(group: group, minutes: minutes)
        refresh()
    }
    func requestRelease() throws { try AdHocMonitoring.requestRelease(); refresh() }
    func release() { AdHocMonitoring.release(); refresh() }
}
