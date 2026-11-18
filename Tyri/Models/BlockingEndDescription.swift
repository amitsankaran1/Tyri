import Foundation

/// A timer expiring must not promise to release independent manual enforcement.
enum BlockingEndDescription {
    static func scheduledManualAction(end: Date, now: Date) -> String {
        "Block until \(scheduledManualTime(end, now: now))"
    }

    static func scheduledManualDetail(end: Date, now: Date = Date()) -> String {
        let time = scheduledManualTime(end, now: now)
        return Calendar.current.isDate(end, inSameDayAs: now) ? "On until \(time) today" : "On until \(time)"
    }

    private static func scheduledManualTime(_ end: Date, now: Date) -> String {
        if Calendar.current.isDate(end, inSameDayAs: now) {
            return end.formatted(date: .omitted, time: .shortened)
        }
        return end.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func detail(timedEnd: Date?, manual: Bool, tag: Bool, now: Date = Date()) -> String {
        if let end = timedEnd, end > now {
            let time = end.formatted(date: Calendar.current.isDate(end, inSameDayAs: now) ? .omitted : .abbreviated,
                                     time: .shortened)
            return manual
                ? "Timed block ends at \(time). Block now stays on until you stop it."
                : "Unblocks at \(time)"
        }
        if tag { return "Until you scan your tag" }
        return manual ? "Block now is on until you stop it." : "Checking when this block ends…"
    }
}
