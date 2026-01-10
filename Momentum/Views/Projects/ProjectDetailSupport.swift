import Foundation

enum UsageWindow: String, CaseIterable, Identifiable {
    case hour
    case day
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: return "1h"
        case .day: return "Hoy"
        case .week: return "7 días"
        }
    }

    var interval: DateInterval {
        let now = Date()
        let calendar = Calendar.current

        switch self {
        case .hour:
            return DateInterval(start: now.addingTimeInterval(-3600), end: now)
        case .day:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, end: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, end: now)
        }
    }
}
