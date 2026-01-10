import Foundation

enum ProjectUsageSummarizer {
    struct UsageSessionSnapshot: Sendable {
        let startDate: Date
        let endDate: Date
        let contextKey: String
        let title: String
        let subtitle: String?
        let bundleIdentifier: String?
        let domain: String?
        let filePath: String?

        nonisolated func duration(in interval: DateInterval) -> TimeInterval {
            let start = max(startDate, interval.start)
            let end = min(endDate, interval.end)
            return max(0, end.timeIntervalSince(start))
        }
    }

    nonisolated static func summaries(
        from sessions: [UsageSessionSnapshot],
        interval: DateInterval,
        limit: Int,
    ) -> [ContextUsageSummary] {
        guard interval.duration > 0, limit > 0 else { return [] }
        var totals: [String: (title: String, subtitle: String?, seconds: TimeInterval, bundleIdentifier: String?, domain: String?, filePath: String?)] = [:]
        for session in sessions {
            let duration = session.duration(in: interval)
            guard duration > 0 else { continue }
            let info = totals[session.contextKey] ?? (
                session.title,
                session.subtitle,
                0,
                session.bundleIdentifier,
                session.domain,
                session.filePath,
            )
            totals[session.contextKey] = (
                info.title,
                info.subtitle,
                info.seconds + duration,
                info.bundleIdentifier,
                info.domain,
                info.filePath,
            )
        }
        let summaries = totals.map { key, value in
            ContextUsageSummary(
                id: key,
                title: value.title,
                subtitle: value.subtitle,
                seconds: value.seconds,
                bundleIdentifier: value.bundleIdentifier,
                domain: value.domain,
                filePath: value.filePath,
            )
        }
        return Array(summaries.sorted { $0.seconds > $1.seconds }.prefix(limit))
    }
}
