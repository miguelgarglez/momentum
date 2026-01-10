import Foundation
import SwiftData

/// Normalizes and cleans up overlapping tracking sessions.
///
/// `SessionOverlapResolver` is responsible for detecting and resolving cases
/// where multiple sessions would otherwise cover the same wall‑clock time,
/// ensuring that downstream summaries (streaks, weekly reports, etc.) are
/// based on a consistent, non‑overlapping timeline.
struct SessionOverlapResolver {
    let context: ModelContext

    func resolveOverlaps(with interval: DateInterval) -> [(Project?, DateInterval)] {
        let predicate = #Predicate<TrackingSession> {
            $0.endDate > interval.start && $0.startDate < interval.end
        }
        let descriptor = FetchDescriptor<TrackingSession>(predicate: predicate)
        guard let sessions = try? context.fetch(descriptor) else {
            return []
        }

        var removedSegments: [(Project?, DateInterval)] = []
        for session in sessions {
            guard let overlap = session.interval.intersection(with: interval) else { continue }
            removedSegments.append((session.project, overlap))
            adjust(session: session, removing: interval)
        }
        return removedSegments
    }

    private func adjust(session: TrackingSession, removing interval: DateInterval) {
        if interval.start <= session.startDate, interval.end >= session.endDate {
            context.delete(session)
            return
        }

        if interval.start <= session.startDate {
            session.startDate = interval.end
            return
        }

        if interval.end >= session.endDate {
            session.endDate = interval.start
            return
        }

        let trailingSession = TrackingSession(
            startDate: interval.end,
            endDate: session.endDate,
            appName: session.appName,
            bundleIdentifier: session.bundleIdentifier,
            domain: session.domain,
            filePath: session.filePath,
            project: session.project,
        )
        context.insert(trailingSession)
        session.endDate = interval.start
    }
}
