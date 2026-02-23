import Foundation
import SwiftData

@MainActor
struct ManualTimeEntryPreview: Equatable {
    let requestedInterval: DateInterval
    let availableSegments: [DateInterval]
    let requestedSeconds: TimeInterval
    let effectiveSeconds: TimeInterval

    var overlappedSeconds: TimeInterval {
        max(0, requestedSeconds - effectiveSeconds)
    }

    var hasOverlap: Bool {
        overlappedSeconds > 0
    }
}

@MainActor
struct ManualTimeEntrySaveResult: Equatable {
    let insertedSegments: Int
    let requestedSeconds: TimeInterval
    let effectiveSeconds: TimeInterval
}

enum ManualTimeEntryServiceError: LocalizedError {
    case invalidInterval
    case futureDate
    case noAvailableTime
    case missingProject
    case unsupportedSessionSource

    var errorDescription: String? {
        switch self {
        case .invalidInterval:
            return String(localized: "El intervalo no es válido.")
        case .futureDate:
            return String(localized: "No puedes añadir tiempo en el futuro.")
        case .noAvailableTime:
            return String(localized: "No hay tiempo disponible para añadir en ese intervalo.")
        case .missingProject:
            return String(localized: "No pudimos encontrar el proyecto para esta entrada.")
        case .unsupportedSessionSource:
            return String(localized: "Solo se pueden eliminar entradas manuales.")
        }
    }
}

@MainActor
struct ManualTimeEntryService {
    let modelContext: ModelContext

    func preview(for interval: DateInterval) throws -> ManualTimeEntryPreview {
        try validate(interval: interval)
        let resolver = SessionOverlapResolver(context: modelContext)
        let segments = resolver.availableSegments(within: interval)
        let requestedSeconds = interval.duration
        let effectiveSeconds = segments.reduce(0) { $0 + $1.duration }
        return ManualTimeEntryPreview(
            requestedInterval: interval,
            availableSegments: segments,
            requestedSeconds: requestedSeconds,
            effectiveSeconds: effectiveSeconds,
        )
    }

    func save(project: Project, interval: DateInterval) throws -> ManualTimeEntrySaveResult {
        let preview = try preview(for: interval)
        guard preview.effectiveSeconds > 0 else {
            throw ManualTimeEntryServiceError.noAvailableTime
        }

        for segment in preview.availableSegments {
            let session = TrackingSession(
                startDate: segment.start,
                endDate: segment.end,
                appName: String(localized: "Entrada manual"),
                bundleIdentifier: nil,
                domain: nil,
                filePath: nil,
                source: .manualEntry,
                project: project,
            )
            modelContext.insert(session)
            applyDailySummaryDelta(project: project, interval: segment, sign: 1)
        }

        project.markStatsDirty()
        try modelContext.save()

        return ManualTimeEntrySaveResult(
            insertedSegments: preview.availableSegments.count,
            requestedSeconds: preview.requestedSeconds,
            effectiveSeconds: preview.effectiveSeconds,
        )
    }

    func delete(session: TrackingSession) throws {
        guard session.source == .manualEntry else {
            throw ManualTimeEntryServiceError.unsupportedSessionSource
        }
        guard let project = session.project else {
            throw ManualTimeEntryServiceError.missingProject
        }

        applyDailySummaryDelta(project: project, interval: session.interval, sign: -1)
        modelContext.delete(session)
        project.markStatsDirty()
        try modelContext.save()
    }

    private func validate(interval: DateInterval) throws {
        guard interval.duration > 0 else {
            throw ManualTimeEntryServiceError.invalidInterval
        }
        let now = Date()
        guard interval.start <= now, interval.end <= now else {
            throw ManualTimeEntryServiceError.futureDate
        }
    }

    private func applyDailySummaryDelta(project: Project, interval: DateInterval, sign: Double) {
        guard interval.duration > 0, sign != 0 else { return }
        var cursor = DailySummary.normalize(interval.start)
        let calendar = Calendar.current
        while cursor < interval.end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let dayInterval = DateInterval(start: cursor, end: nextDay)
            if let overlap = interval.intersection(with: dayInterval) {
                applyDailySummaryDelta(project: project, day: cursor, deltaSeconds: overlap.duration * sign)
            }
            cursor = nextDay
        }
    }

    private func applyDailySummaryDelta(project: Project, day: Date, deltaSeconds: TimeInterval) {
        guard deltaSeconds != 0 else { return }
        let normalizedDay = DailySummary.normalize(day)
        if let summary = project.dailySummaries.first(where: { $0.date == normalizedDay }) {
            summary.apply(deltaSeconds: deltaSeconds)
            if summary.seconds <= 0 {
                modelContext.delete(summary)
            }
            return
        }
        guard deltaSeconds > 0 else { return }
        let summary = DailySummary(date: normalizedDay, seconds: deltaSeconds, project: project)
        modelContext.insert(summary)
    }
}
