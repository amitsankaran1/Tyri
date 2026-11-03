import Foundation
import DeviceActivity

/// A single temporary session, separate from saved rules. The list is snapshotted
/// so editing or deleting it cannot weaken a session already in progress.
struct AdHocSession: Codable, Identifiable, Equatable {
    var id = UUID()
    let group: AppGroup
    let startedAt: Date
    let endsAt: Date
    var releaseAt: Date? = nil

    var tokens: BlockResolution.Tokens {
        BlockResolution.tokens(for: BlockRule(name: group.name, appGroupIDs: [group.id]), groups: [group])
    }
}

enum AdHocMonitoring {
    static var session: AdHocSession? {
        guard let data = SharedDefaults.suite.data(forKey: SharedDefaults.Keys.adHocSession) else { return nil }
        return try? JSONDecoder().decode(AdHocSession.self, from: data)
    }

    static func save(_ session: AdHocSession) throws {
        SharedDefaults.suite.set(try JSONEncoder().encode(session), forKey: SharedDefaults.Keys.adHocSession)
    }

    static func activityName(_ id: UUID) -> DeviceActivityName {
        DeviceActivityName(rawValue: "adhoc.\(id.uuidString)")
    }

    static func start(group: AppGroup, minutes: Int, now: Date = Date()) throws {
        reconcile(now: now)
        guard session == nil, (15...1440).contains(minutes) else {
            throw SessionError.invalidDurationOrActive
        }
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        let item = AdHocSession(group: group, startedAt: start, endsAt: start.addingTimeInterval(Double(minutes * 60)))
        guard !item.tokens.isEmpty || !item.tokens.domains.isEmpty else { throw SessionError.emptyList }
        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
            intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.endsAt), repeats: false)
        // No shielding unless background expiry registration succeeds.
        try save(item)
        do {
            try DeviceActivityCenter().startMonitoring(activityName(item.id), during: schedule)
        } catch {
            finish(id: item.id)
            throw error
        }
        BlockingActuator.apply(tokens: item.tokens, blockID: item.id)
    }

    static func reconcile(now: Date = Date()) {
        guard let item = session else { return }
        if item.endsAt <= now { finish(id: item.id) }
        else { BlockingActuator.apply(tokens: item.tokens, blockID: item.id) }
    }

    static func requestRelease(now: Date = Date()) throws {
        guard var item = session, item.endsAt > now, item.releaseAt == nil else { return }
        item.releaseAt = now.addingTimeInterval(300)
        try save(item)
    }

    /// Wait completion never silently releases. Requires an explicit tap.
    static func release(now: Date = Date()) {
        guard let item = session, let releaseAt = item.releaseAt, releaseAt <= now else { return }
        finish(id: item.id)
    }

    static func finish(id: UUID) {
        guard session?.id == id else { return }
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.adHocSession)
        DeviceActivityCenter().stopMonitoring([activityName(id)])
        BlockingActuator.clearShields(blockID: id)
    }

    enum SessionError: LocalizedError {
        case invalidDurationOrActive, emptyList
        var errorDescription: String? {
            switch self {
            case .invalidDurationOrActive: return "Choose 15 minutes to 24 hours, and finish your current session first."
            case .emptyList: return "This list has no apps or websites. Add some in Lists first."
            }
        }
    }
}
