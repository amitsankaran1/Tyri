//
//  BlockingSchedule.swift
//  Tyri
//
//  Add target membership to BOTH Tyri and TyriMonitor targets.
//

import Foundation
#if canImport(DeviceActivity) && os(iOS)
import DeviceActivity
#endif

/// Time-of-day weekly schedule for a blocking preset.
///
/// `weekdays` follows `Calendar.Component.weekday` convention:
/// 1 = Sunday, 2 = Monday, … 7 = Saturday.
struct BlockingSchedule: Codable, Equatable, Hashable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var weekdays: Set<Int>
    var repeats: Bool

    init(
        startHour: Int = 9,
        startMinute: Int = 0,
        endHour: Int = 17,
        endMinute: Int = 0,
        weekdays: Set<Int> = [2, 3, 4, 5, 6],
        repeats: Bool = true
    ) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.weekdays = weekdays
        self.repeats = repeats
    }

    var startMinutesFromMidnight: Int { startHour * 60 + startMinute }
    var endMinutesFromMidnight: Int { endHour * 60 + endMinute }

    /// True when the schedule wraps past midnight (end is on or before start).
    var crossesMidnight: Bool { endMinutesFromMidnight <= startMinutesFromMidnight }

    /// The selected weekday is the day the window STARTS, including after midnight.
    /// End is exclusive. Calendar arithmetic preserves local wall times across DST.
    func activeWindow(at now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day),
                  let endDay = calendar.date(byAdding: .day, value: crossesMidnight ? 1 : 0, to: day),
                  let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: endDay),
                  start <= now, now < end else { continue }
            return DateInterval(start: start, end: end)
        }
        return nil
    }

    /// Short human label like "Mon–Fri 9:00–17:00".
    var summary: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "H:mm"
        let startDate = Calendar.current.date(from: DateComponents(hour: startHour, minute: startMinute)) ?? Date()
        let endDate = Calendar.current.date(from: DateComponents(hour: endHour, minute: endMinute)) ?? Date()
        let timeRange = "\(timeFormatter.string(from: startDate))–\(timeFormatter.string(from: endDate))"
        return "\(weekdaySummary) \(timeRange)"
    }

    var weekdaySummary: String {
        if weekdays.count == 7 { return "Every day" }
        if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        let ordered = weekdays.sorted()
        return ordered.compactMap { day -> String? in
            let index = day - 1
            return (index >= 0 && index < symbols.count) ? symbols[index] : nil
        }.joined(separator: " ")
    }

#if canImport(DeviceActivity) && os(iOS)
    /// A single interval also spans midnight; legacy segment names are cleanup-only.
    func deviceActivitySchedule(crossingSegment: CrossingSegment = .full) -> DeviceActivitySchedule {
        switch crossingSegment {
        case .full:
            return DeviceActivitySchedule(
                intervalStart: DateComponents(hour: startHour, minute: startMinute),
                intervalEnd: DateComponents(hour: endHour, minute: endMinute),
                repeats: repeats
            )
        case .early:
            // start → 23:59 (covers from start time to end of day)
            return DeviceActivitySchedule(
                intervalStart: DateComponents(hour: startHour, minute: startMinute),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: repeats
            )
        case .late:
            // 00:00 → end (covers early morning)
            return DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: endHour, minute: endMinute),
                repeats: repeats
            )
        }
    }

    enum CrossingSegment {
        case full
        case early
        case late
    }
#endif
}
