//
//  DailySummary.swift
//  Momentum
//
//  Created by Codex on 24/11/25.
//

import Foundation

struct DailySummary: Identifiable {
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
