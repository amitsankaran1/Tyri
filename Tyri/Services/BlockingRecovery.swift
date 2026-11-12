import Foundation
import FamilyControls

/// A repair action never grants a healthy usage allowance a fresh counter.
@MainActor
enum BlockingRecovery {
    @discardableResult
    static func retry(blockID: UUID) -> Bool {
        guard let transition = EnforcementTransaction.begin() else { return false }
        defer { ForegroundRecovery.shared.finish(transition) }
        let screenTime = ScreenTimeManager.shared
        screenTime.checkAuthorizationStatus()
        guard screenTime.authorizationStatus == .approved,
              let block = BlockStore.shared.block(id: blockID) else { return false }
        switch block.type {
        case .timer:
            UsageLimitManager.shared.applyUsageLimit(for: block, forceReset: false)
        case .schedule:
            SchedulingManager.shared.applySchedule(for: block)
        case .tag:
            break
        }
        screenTime.updateBlockShieldIfActive(block)
        SchedulingManager.shared.refresh()
        UsageLimitManager.shared.refresh()
        return true
    }
}
