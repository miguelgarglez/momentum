//
//  Project.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftUI
import SwiftData

@Model
final class Project {
    var name: String
    var colorHex: String
    var iconName: String
    var assignedAppsRaw: String = "[]"
    var assignedDomainsRaw: String = "[]"
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TrackingSession.project)
    var sessions: [TrackingSession] = []

    init(
        name: String,
        colorHex: String = ProjectPalette.defaultColor.hex,
        iconName: String = ProjectIcon.spark.rawValue,
        assignedApps: [String] = [],
        assignedDomains: [String] = []
    ) {
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.assignedAppsRaw = Project.encode(strings: assignedApps)
        self.assignedDomainsRaw = Project.encode(strings: assignedDomains.map { $0.lowercased() })
        self.createdAt = Date()
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

    var color: Color { Color(hex: colorHex) ?? .accentColor }
    
    var lastActivityDate: Date? {
        sessions.sorted(by: { $0.endDate > $1.endDate }).first?.endDate
    }
    
    var lastActivityText: String {
        guard let last = lastActivityDate else { return "Sin datos recientes" }
        return RelativeDateTimeFormatter().localizedString(for: last, relativeTo: .now)
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
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let interval = DateInterval(start: startOfWeek, end: .now)
        return secondsSpent(in: interval)
    }
    
    var dailySeconds: TimeInterval {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let interval = DateInterval(start: startOfDay, end: .now)
        return secondsSpent(in: interval)
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
}

private extension Project {
    static func encode(strings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(strings),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func decodeStrings(from string: String) -> [String] {
        guard let data = string.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }
}

extension Project {
    func recentDailySummaries(limit: Int = 7) -> [DailySummary] {
        guard limit > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = (0..<limit).compactMap { offset -> DailySummary? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }
            let interval = DateInterval(start: day, end: end)
            let seconds = secondsSpent(in: interval)
            return DailySummary(date: day, seconds: seconds)
        }
        return days.reversed()
    }

    func contextUsageSummaries(for interval: DateInterval, limit: Int = 6) -> [ContextUsageSummary] {
        guard interval.duration > 0 else { return [] }
        var totals: [String: (title: String, subtitle: String?, seconds: TimeInterval, bundleIdentifier: String?, domain: String?)] = [:]
        for session in sessions {
            let duration = session.duration(in: interval)
            guard duration > 0 else { continue }
            let key = session.contextKey
            let info = totals[key] ?? (session.primaryContextLabel, session.secondaryContextLabel, 0, session.bundleIdentifier, session.domain)
            totals[key] = (info.title, info.subtitle, info.seconds + duration, session.bundleIdentifier, session.domain)
        }
        let summaries = totals.map { key, value in
            ContextUsageSummary(
                id: key,
                title: value.title,
                subtitle: value.subtitle,
                seconds: value.seconds,
                bundleIdentifier: value.bundleIdentifier,
                domain: value.domain
            )
        }
        return Array(summaries.sorted { $0.seconds > $1.seconds }.prefix(limit))
    }

}

enum ProjectIcon: String, CaseIterable {
    case spark = "sparkles"
    case book = "book"
    case hammer = "hammer"
    case paint = "paintbrush"
    case bolt = "bolt"

    var systemName: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .spark: return "Momentum"
        case .book: return "Estudio"
        case .hammer: return "Construir"
        case .paint: return "Creativo"
        case .bolt: return "Energía"
        }
    }
}

struct ProjectColor: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
}

enum ProjectPalette {
    static let colors: [ProjectColor] = [
        ProjectColor(name: "Coral", hex: "#FE7A71"),
        ProjectColor(name: "Sunset", hex: "#FFB347"),
        ProjectColor(name: "Forest", hex: "#1F9D55"),
        ProjectColor(name: "Ocean", hex: "#009FB7"),
        ProjectColor(name: "Indigo", hex: "#5C6AC4"),
        ProjectColor(name: "Lavender", hex: "#A78BFA")
    ]

    static var defaultColor: ProjectColor { colors[0] }
}

struct ContextUsageSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let seconds: TimeInterval
    let bundleIdentifier: String?
    let domain: String?
}
