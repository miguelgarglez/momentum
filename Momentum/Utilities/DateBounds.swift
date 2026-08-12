import Foundation

enum DateBounds: Sendable {
    nonisolated static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    nonisolated static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = startOfDay(date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Inclusive start of the window covering `dayCount` calendar days ending today.
    nonisolated static func startOfLastDays(_ dayCount: Int, from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = startOfDay(date, calendar: calendar)
        return calendar.date(byAdding: .day, value: -(max(1, dayCount) - 1), to: today) ?? today
    }
}
