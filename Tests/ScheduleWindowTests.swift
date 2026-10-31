import Foundation

@main
struct ScheduleWindowTests {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let parser = ISO8601DateFormatter()
        func date(_ value: String) -> Date { parser.date(from: value)! }
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let daily = BlockingSchedule(startHour: 20, endHour: 10, weekdays: Set(1...7))
        for instant in ["2026-10-30T21:39:00-04:00", "2026-10-30T09:39:00-04:00", "2026-10-30T23:59:30-04:00", "2026-10-31T00:00:00-04:00"] {
            check(daily.activeWindow(at: date(instant), calendar: cal) != nil, "Video/overnight time must be blocked: \(instant)")
        }
        check(daily.activeWindow(at: date("2026-10-30T10:00:00-04:00"), calendar: cal) == nil, "End exclusive")
        check(daily.activeWindow(at: date("2026-10-30T19:59:59-04:00"), calendar: cal) == nil, "Before start")
        check(daily.activeWindow(at: date("2026-10-30T20:00:00-04:00"), calendar: cal) != nil, "Start inclusive")
        let friday = BlockingSchedule(startHour: 20, endHour: 10, weekdays: [6])
        check(friday.activeWindow(at: date("2026-10-31T09:39:00-04:00"), calendar: cal) != nil, "Friday continues Saturday")
        check(friday.activeWindow(at: date("2026-10-30T09:39:00-04:00"), calendar: cal) == nil, "Friday morning belongs to Thursday")
        let saturday = BlockingSchedule(startHour: 10, endHour: 20, weekdays: [7])
        check(saturday.activeWindow(at: date("2026-10-30T15:00:00-04:00"), calendar: cal) == nil, "Unselected day")
        check(saturday.activeWindow(at: date("2026-10-31T15:00:00-04:00"), calendar: cal) != nil, "Selected daytime")
        for instant in ["2026-11-01T01:30:00-04:00", "2026-11-01T01:30:00-05:00", "2026-03-08T03:30:00-04:00"] {
            check(daily.activeWindow(at: date(instant), calendar: cal) != nil, "DST overnight: \(instant)")
        }
        let fullDay = BlockingSchedule(startHour: 9, endHour: 9, weekdays: [6])
        check(fullDay.activeWindow(at: date("2026-10-31T08:59:59-04:00"), calendar: cal) != nil, "Equal times span one day")
        check(fullDay.activeWindow(at: date("2026-10-31T09:00:00-04:00"), calendar: cal) == nil, "Full day ends")
        print("PASS: \(checks) schedule window regression checks")
    }
}
