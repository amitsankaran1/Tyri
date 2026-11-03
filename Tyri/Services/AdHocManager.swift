import Foundation
import Combine
import FamilyControls

@MainActor
final class AdHocManager: ObservableObject {
    static let shared = AdHocManager()
    @Published private(set) var session: AdHocSession?
    private init() { session = AdHocMonitoring.session }
    func refresh(reconcile: Bool = true) {
        if reconcile || (AdHocMonitoring.session.map { $0.endsAt <= Date() } ?? false) { AdHocMonitoring.reconcile() }
        session = AdHocMonitoring.session
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
