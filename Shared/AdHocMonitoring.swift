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
        let base = "adhoc.\(id.uuidString)"
        return DeviceActivityName(rawValue: MonitorRegistration.current(base, legacyName: base))
    }

    static func registrationContext(_ session: AdHocSession) -> String {
        String(session.endsAt.timeIntervalSince1970.bitPattern, radix: 16)
    }

    static func start(group: AppGroup, minutes: Int, now: Date = Date()) throws {
        guard let transition = EnforcementTransaction.begin() else { throw SessionError.unavailable }
        defer { transition.finish() }

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
        let base = "adhoc.\(item.id.uuidString)"
        guard let ticket = MonitorRegistration.reserve(base, legacyName: base, context: registrationContext(item)) else { throw SessionError.unavailable }
        do {
            try DeviceActivityCenter().startMonitoring(DeviceActivityName(rawValue: ticket.name), during: schedule)
        } catch {
            _ = MonitorRegistration.finish(ticket, context: registrationContext(item), succeeded: false)
            finish(id: item.id)
            throw error
        }
        // A reentrant completion or cancellation must never resurrect this owner.
        guard session?.id == item.id else { return }
        _ = MonitorRegistration.finish(ticket, context: registrationContext(item), succeeded: true)
        BlockingActuator.apply(tokens: item.tokens, blockID: item.id)
    }

    static func reconcile(now: Date = Date()) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard let item = session else { return }
        if item.endsAt <= now { finish(id: item.id) }
        else {
            if !DeviceActivityCenter().activities.contains(activityName(item.id)) {
                let cal = Calendar.current
                // Preserve the deadline. Short remaining windows use the warning
                // callback, just like short usage lockouts and breaks.
                let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
                let monitorEnd = max(item.endsAt, start.addingTimeInterval(900))
                let warning = Int(ceil(monitorEnd.timeIntervalSince(item.endsAt)))
                let schedule = DeviceActivitySchedule(
                    intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start),
                    intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: monitorEnd),
                    repeats: false, warningTime: warning > 0 ? DateComponents(second: warning) : nil)
                let base = "adhoc.\(item.id.uuidString)"
                guard let ticket = MonitorRegistration.reserve(base, legacyName: base, context: registrationContext(item)) else { return }
                do {
                    try DeviceActivityCenter().startMonitoring(DeviceActivityName(rawValue: ticket.name), during: schedule)
                    _ = MonitorRegistration.finish(ticket, context: session?.id == item.id ? registrationContext(item) : nil, succeeded: true)
                    SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: item.id))
                } catch {
                    _ = MonitorRegistration.finish(ticket, context: registrationContext(item), succeeded: false)
                    SharedDefaults.suite.set("Automatic end could not be restored. Open Tyri at the end of this session.",
                                             forKey: SharedDefaults.Keys.usageLockError(blockID: item.id))
                }
            }
            guard session?.id == item.id else { return }
            BlockingActuator.apply(tokens: item.tokens, blockID: item.id)
        }
    }

    static func requestRelease(now: Date = Date()) throws {
        guard let transition = EnforcementTransaction.begin() else { throw SessionError.unavailable }
        defer { transition.finish() }

        guard var item = session, item.endsAt > now, item.releaseAt == nil else { return }
        item.releaseAt = now.addingTimeInterval(300)
        try save(item)
    }

    /// Wait completion never silently releases. Requires an explicit tap.
    static func release(now: Date = Date()) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard let item = session, let releaseAt = item.releaseAt, releaseAt <= now else { return }
        finish(id: item.id)
    }

    static func finish(id: UUID, stopMonitoring: Bool = true) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        guard session?.id == id else { return }
        let activity = activityName(id)
        MonitorRegistration.invalidate("adhoc.\(id.uuidString)", legacyName: "adhoc.\(id.uuidString)")
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.adHocSession)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.usageLockError(blockID: id))
        if stopMonitoring { DeviceActivityCenter().stopMonitoring([activity]) }
        BlockingActuator.clearShields(blockID: id)
    }

    enum SessionError: LocalizedError {
        case invalidDurationOrActive, emptyList, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidDurationOrActive: return "Choose 15 minutes to 24 hours, and finish your current session first."
            case .unavailable: return "Blocking state is unavailable. Please reopen Tyri and retry."
            case .emptyList: return "This list has no apps or websites. Add some in Lists first."
            }
        }
    }
}
