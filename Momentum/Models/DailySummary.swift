//
//  DailySummary.swift
//  Momentum
//
//  Created by Codex on 24/11/25.
//

import Foundation
import SwiftData

@Model
final class DailySummary {
    var date: Date
    var seconds: TimeInterval
    var project: Project?
    var createdAt: Date
    var updatedAt: Date

    init(date: Date, seconds: TimeInterval = 0, project: Project?) {
        let normalized = DailySummary.normalize(date)
        self.date = normalized
        self.seconds = seconds
        self.project = project
        let now = Date()
        createdAt = now
        updatedAt = now
    }

    func apply(deltaSeconds: TimeInterval) {
        guard deltaSeconds != 0 else { return }
        seconds = max(0, seconds + deltaSeconds)
        updatedAt = Date()
    }

    static func normalize(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

struct DailySummaryPoint: Identifiable {
    var date: Date
    var seconds: TimeInterval
    var id: Date { date }

    var label: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}
