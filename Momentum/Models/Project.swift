//
//  Project.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Project {
    var name: String
    var colorHex: String
    var iconName: String
    var assignedAppsRaw: String = "[]"
    var assignedDomainsRaw: String = "[]"
    var assignedFilesRaw: String = "[]"
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TrackingSession.project)
    var sessions: [TrackingSession] = []
    @Relationship(deleteRule: .cascade, inverse: \DailySummary.project)
    var dailySummaries: [DailySummary] = []

    init(
        name: String,
        colorHex: String = ProjectPalette.defaultColor.hex,
        iconName: String = ProjectIcon.spark.rawValue,
        assignedApps: [String] = [],
        assignedDomains: [String] = [],
        assignedFiles: [String] = [],
    ) {
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        assignedAppsRaw = Project.encode(strings: assignedApps)
        assignedDomainsRaw = Project.encode(strings: assignedDomains.map { $0.lowercased() })
        assignedFilesRaw = Project.encode(strings: Project.normalizeFiles(assignedFiles))
        createdAt = Date()
    }
}

extension Project {
    var assignedApps: [String] {
        get { Project.decodeStrings(from: assignedAppsRaw) }
        set { assignedAppsRaw = Project.encode(strings: newValue) }
    }

    var assignedDomains: [String] {
        get { Project.decodeStrings(from: assignedDomainsRaw) }
        set { assignedDomainsRaw = Project.encode(strings: newValue.map { $0.lowercased() }) }
    }

    var assignedFiles: [String] {
        get { Project.decodeStrings(from: assignedFilesRaw) }
        set { assignedFilesRaw = Project.encode(strings: Project.normalizeFiles(newValue)) }
    }

    var color: Color { Color(hex: colorHex) ?? .accentColor }

    @MainActor
    var lastActivityDate: Date? {
        sessions.max(by: { $0.endDate < $1.endDate })?.endDate
    }

    @MainActor
    var lastActivityText: String {
        guard let last = lastActivityDate else { return "Sin datos recientes" }
        return Self.relativeDateFormatter.localizedString(for: last, relativeTo: .now)
    }

    func secondsSpent(in interval: DateInterval) -> TimeInterval {
        sessions.reduce(0) { partialResult, session in
            guard let overlap = session.interval.intersection(with: interval) else {
                return partialResult
            }
            return partialResult + overlap.duration
        }
    }

    var totalSeconds: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var weeklySeconds: TimeInterval {
        let calendar = Calendar.current
        let end = Date()
        let startOfWindow = calendar.date(byAdding: .day, value: -6, to: DailySummary.normalize(end)) ?? end
        guard !dailySummaries.isEmpty else {
            let interval = DateInterval(start: startOfWindow, end: end)
            return secondsSpent(in: interval)
        }
        return dailySummaries.reduce(0) { partial, summary in
            summary.date >= startOfWindow ? partial + summary.seconds : partial
        }
    }

    var dailySeconds: TimeInterval {
        let startOfDay = DailySummary.normalize(.now)
        if let cached = dailySummaries.first(where: { $0.date == startOfDay }) {
            return cached.seconds
        }
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? .now
        let interval = DateInterval(start: startOfDay, end: min(endOfDay, .now))
        return secondsSpent(in: interval)
    }

    var monthlySeconds: TimeInterval {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.dateInterval(of: .month, for: .now)?.start else {
            return 0
        }
        guard !dailySummaries.isEmpty else {
            let interval = DateInterval(start: startOfMonth, end: .now)
            return secondsSpent(in: interval)
        }
        return dailySummaries.reduce(0) { partial, summary in
            summary.date >= startOfMonth ? partial + summary.seconds : partial
        }
    }

    var streakCount: Int {
        let calendar = Calendar.current
        var streak = 0
        var date = calendar.startOfDay(for: .now)

        while hasActivity(on: date) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else {
                break
            }
            date = previous
        }

        return streak
    }

    var longestStreakCount: Int {
        let sortedDays = activityDays().sorted()
        guard let firstDay = sortedDays.first else { return 0 }
        let calendar = Calendar.current
        var best = 1
        var current = 1
        var previous = firstDay

        for day in sortedDays.dropFirst() {
            guard let expected = calendar.date(byAdding: .day, value: 1, to: previous) else {
                current = 1
                previous = day
                best = max(best, current)
                continue
            }
            if day == expected {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }

        return best
    }

    func hasActivity(on date: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return false
        }
        let interval = DateInterval(start: start, end: end)
        return !sessions.filter { $0.interval.intersects(interval) }.isEmpty
    }

    func matches(appBundleIdentifier: String) -> Bool {
        assignedApps.contains { $0.caseInsensitiveCompare(appBundleIdentifier) == .orderedSame }
    }

    func matches(domain: String) -> Bool {
        assignedDomains.contains { domain.lowercased().contains($0) }
    }

    func matches(filePath: String) -> Bool {
        let normalized = filePath.normalizedFilePath
        guard !normalized.isEmpty else { return false }
        return assignedFiles.contains { $0.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    func addAssignedApp(_ bundleIdentifier: String) {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if assignedApps.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return
        }
        assignedApps.append(normalized)
    }

    func addAssignedDomain(_ domain: String) {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        if assignedDomains.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return
        }
        assignedDomains.append(normalized)
    }

    func addAssignedFile(_ filePath: String) {
        let normalized = filePath.normalizedFilePath
        guard !normalized.isEmpty else { return }
        if assignedFiles.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return
        }
        assignedFiles.append(normalized)
    }

    @MainActor
    func apply(draft: ProjectFormDraft) {
        name = draft.name
        colorHex = draft.colorHex
        iconName = draft.iconName
        assignedApps = draft.assignedApps
        assignedDomains = draft.assignedDomains
        assignedFiles = draft.assignedFiles
    }
}

private extension Project {
    func activityDays() -> Set<Date> {
        let calendar = Calendar.current
        var days: Set<Date> = []

        for summary in dailySummaries where summary.seconds > 0 {
            days.insert(summary.date)
        }

        for session in sessions {
            let interval = session.interval
            guard interval.duration > 0 else { continue }
            var cursor = calendar.startOfDay(for: interval.start)
            while cursor < interval.end {
                days.insert(cursor)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = nextDay
            }
        }

        return days
    }
}

private extension Project {
    static func encode(strings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(strings),
              let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }

    static func decodeStrings(from string: String) -> [String] {
        guard let data = string.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }

    static func normalizeFiles(_ files: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for file in files {
            let normalized = file.normalizedFilePath
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            if seen.insert(key).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}

extension Project {
    func recentDailySummaries(limit: Int = 7) -> [DailySummaryPoint] {
        guard limit > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let cached = dailySummaries.reduce(into: [Date: TimeInterval]()) { partial, summary in
            partial[summary.date] = summary.seconds
        }
        let days = (0 ..< limit).compactMap { offset -> DailySummaryPoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day)
            else {
                return nil
            }
            let normalized = calendar.startOfDay(for: day)
            let seconds = cached[normalized] ?? secondsSpent(in: DateInterval(start: normalized, end: end))
            return DailySummaryPoint(date: normalized, seconds: seconds)
        }
        return days.reversed()
    }

    func dailySummarySeconds(for date: Date) -> TimeInterval {
        let normalized = DailySummary.normalize(date)
        if let cached = dailySummaries.first(where: { $0.date == normalized }) {
            return cached.seconds
        }
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: normalized) else {
            return 0
        }
        return secondsSpent(in: DateInterval(start: normalized, end: end))
    }

    func dailySummaries(in interval: DateInterval) -> [DailySummaryPoint] {
        guard interval.duration > 0 else { return [] }
        let calendar = Calendar.current
        let start = DailySummary.normalize(interval.start)
        let totals = dailySummaryTotals(in: interval)
        var points: [DailySummaryPoint] = []
        var cursor = start
        while cursor < interval.end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            points.append(DailySummaryPoint(date: cursor, seconds: totals[cursor, default: 0]))
            cursor = nextDay
        }
        return points
    }

    private func dailySummaryTotals(in interval: DateInterval) -> [Date: TimeInterval] {
        guard interval.duration > 0 else { return [:] }
        let calendar = Calendar.current
        let start = DailySummary.normalize(interval.start)
        let end = interval.end

        var totals: [Date: TimeInterval] = [:]
        if !dailySummaries.isEmpty {
            for summary in dailySummaries where summary.date >= start && summary.date < end {
                totals[summary.date] = summary.seconds
            }
        }

        let expectedDays = daysBetween(start: start, end: end, calendar: calendar)
        guard totals.count < expectedDays else { return totals }

        var sessionTotals: [Date: TimeInterval] = [:]
        for session in sessions {
            let sessionInterval = session.interval
            guard sessionInterval.intersects(interval),
                  let clipped = sessionInterval.intersection(with: interval)
            else {
                continue
            }
            var cursor = DailySummary.normalize(clipped.start)
            while cursor < clipped.end {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                let dayInterval = DateInterval(start: cursor, end: nextDay)
                if let overlap = clipped.intersection(with: dayInterval) {
                    sessionTotals[cursor, default: 0] += overlap.duration
                }
                cursor = nextDay
            }
        }

        for (day, seconds) in sessionTotals where totals[day] == nil {
            totals[day] = seconds
        }

        return totals
    }

    private func daysBetween(start: Date, end: Date, calendar: Calendar) -> Int {
        var count = 0
        var cursor = start
        while cursor < end {
            count += 1
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return count
    }

    func contextUsageSummaries(for interval: DateInterval, limit: Int = 6) -> [ContextUsageSummary] {
        guard interval.duration > 0 else { return [] }
        var totals: [String: (title: String, subtitle: String?, seconds: TimeInterval, bundleIdentifier: String?, domain: String?, filePath: String?)] = [:]
        for session in sessions {
            let duration = session.duration(in: interval)
            guard duration > 0 else { continue }
            let key = session.contextKey
            let info = totals[key] ?? (session.primaryContextLabel, session.secondaryContextLabel, 0, session.bundleIdentifier, session.domain, session.filePath)
            totals[key] = (info.title, info.subtitle, info.seconds + duration, session.bundleIdentifier, session.domain, session.filePath)
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

private extension Project {
    @MainActor
    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

enum ProjectIcon: String, CaseIterable {
    case spark = "sparkles"
    case book
    case hammer
    case paint = "paintbrush"
    case bolt

    var systemName: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .spark: "Momentum"
        case .book: "Estudio"
        case .hammer: "Construir"
        case .paint: "Creativo"
        case .bolt: "Energía"
        }
    }
}

struct ProjectColor: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
}

enum ProjectPalette {
    nonisolated static let colors: [ProjectColor] = [
        ProjectColor(name: "Coral", hex: "#FE7A71"),
        ProjectColor(name: "Sunset", hex: "#FFB347"),
        ProjectColor(name: "Forest", hex: "#1F9D55"),
        ProjectColor(name: "Ocean", hex: "#009FB7"),
        ProjectColor(name: "Indigo", hex: "#5C6AC4"),
        ProjectColor(name: "Lavender", hex: "#A78BFA"),
    ]

    nonisolated static var defaultColor: ProjectColor { colors[0] }
}

struct ContextUsageSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let seconds: TimeInterval
    let bundleIdentifier: String?
    let domain: String?
    let filePath: String?
}
