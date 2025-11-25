//
//  TrackingSession.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftData

@Model
final class TrackingSession {
    var startDate: Date
    var endDate: Date
    var appName: String
    var bundleIdentifier: String?
    var domain: String?
    var project: Project?

    init(
        startDate: Date,
        endDate: Date,
        appName: String,
        bundleIdentifier: String?,
        domain: String?,
        project: Project?
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.domain = domain
        self.project = project
    }
}

extension TrackingSession {
    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    var interval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }

    var sourceLabel: String {
        if let domain {
            return domain
        }
        return bundleIdentifier ?? appName
    }
}
