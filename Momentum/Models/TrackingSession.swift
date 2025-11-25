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

    var contextKey: String {
        if let domain {
            return "domain::\(domain.lowercased())"
        }
        if let bundleIdentifier {
            return "bundle::\(bundleIdentifier)"
        }
        return "app::\(appName)"
    }

    var primaryContextLabel: String {
        domain ?? appName
    }

    var secondaryContextLabel: String? {
        domain == nil ? nil : appName
    }

    func duration(in interval: DateInterval) -> TimeInterval {
        guard let overlap = self.interval.intersection(with: interval) else {
            return 0
        }
        return overlap.duration
    }
}
