//
//  DailySummaryBackfill.swift
//  Momentum
//
//  Created by Codex on 02/01/26.
//

import Foundation
import OSLog
import SwiftData

protocol DailySummaryBackfilling {
    func runIfNeeded(container: ModelContainer)
}

final class DailySummaryBackfill: DailySummaryBackfilling {
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "DailySummaryBackfill")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func runIfNeeded(container: ModelContainer) {
        let storedVersion = defaults.integer(forKey: Keys.version)
        guard storedVersion < Constants.currentVersion else { return }

        Task.detached(priority: .utility) { [defaults, logger] in
            do {
                try DailySummaryBackfill.backfill(container: container)
                defaults.set(Constants.currentVersion, forKey: Keys.version)
                logger.info("DailySummary backfill completed.")
            } catch {
                logger.error("DailySummary backfill failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func backfill(container: ModelContainer) throws {
        let context = ModelContext(container)
        let projects = try context.fetch(FetchDescriptor<Project>())
        guard !projects.isEmpty else { return }

        for project in projects {
            let sessions = project.sessions
            guard !sessions.isEmpty else { continue }

            var totals: [Date: TimeInterval] = [:]
            for session in sessions {
                let interval = session.interval
                guard interval.duration > 0 else { continue }
                var cursor = DailySummary.normalize(interval.start)
                let calendar = Calendar.current
                while cursor < interval.end {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                    let dayInterval = DateInterval(start: cursor, end: nextDay)
                    if let overlap = interval.intersection(with: dayInterval) {
                        totals[cursor, default: 0] += overlap.duration
                    }
                    cursor = nextDay
                }
            }

            let existing = Set(project.dailySummaries.map(\.date))
            for (day, seconds) in totals where seconds > 0 && !existing.contains(day) {
                let summary = DailySummary(date: day, seconds: seconds, project: project)
                context.insert(summary)
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }
}

private enum Constants {
    static let currentVersion = 1
}

private enum Keys {
    static let version = "dailySummary.backfill.version"
}
