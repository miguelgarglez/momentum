//
//  TimeFormatting.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation

extension TimeInterval {
    var hoursAndMinutesString: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }
}
