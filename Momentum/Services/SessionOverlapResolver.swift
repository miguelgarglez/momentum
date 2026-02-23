import Foundation
import SwiftData

/// Normalizes and cleans up overlapping tracking sessions.
///
/// `SessionOverlapResolver` is responsible for detecting and resolving cases
/// where multiple sessions would otherwise cover the same wall‑clock time,
/// ensuring that downstream summaries (streaks, weekly reports, etc.) are
/// based on a consistent, non‑overlapping timeline.
@MainActor
struct SessionOverlapResolver {
    let context: ModelContext

    func overlappingIntervals(with interval: DateInterval) -> [DateInterval] {
        let predicate = #Predicate<TrackingSession> {
            $0.endDate > interval.start && $0.startDate < interval.end
        }
        let descriptor = FetchDescriptor<TrackingSession>(predicate: predicate)
        guard let sessions = try? Diagnostics.record(.swiftDataFetch, work: {
            try context.fetch(descriptor)
        }) else {
            return []
        }
        return sessions
            .compactMap { $0.interval.intersection(with: interval) }
            .sorted { $0.start < $1.start }
    }

    func availableSegments(within interval: DateInterval) -> [DateInterval] {
        guard interval.duration > 0 else { return [] }
        let overlaps = overlappingIntervals(with: interval)
        guard !overlaps.isEmpty else { return [interval] }

        var segments: [DateInterval] = []
        var cursor = interval.start
        for overlap in overlaps {
            if overlap.start > cursor {
                segments.append(DateInterval(start: cursor, end: overlap.start))
            }
            if overlap.end > cursor {
                cursor = overlap.end
            }
            if cursor >= interval.end {
                break
            }
        }

        if cursor < interval.end {
            segments.append(DateInterval(start: cursor, end: interval.end))
        }
        return segments.filter { $0.duration > 0 }
    }

    func resolveOverlaps(with interval: DateInterval) -> [(Project?, DateInterval)] {
        let predicate = #Predicate<TrackingSession> {
            $0.endDate > interval.start && $0.startDate < interval.end
        }
        let descriptor = FetchDescriptor<TrackingSession>(predicate: predicate)
        guard let sessions = try? Diagnostics.record(.swiftDataFetch, work: {
            try context.fetch(descriptor)
        }) else {
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
            source: session.source,
            project: session.project,
        )
        context.insert(trailingSession)
        session.endDate = interval.start
    }
}
