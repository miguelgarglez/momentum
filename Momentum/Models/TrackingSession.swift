//
//  TrackingSession.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftData

enum TrackingSessionSource: String, CaseIterable {
    case automatic
    case manualLive
    case manualEntry
}

@Model
final class TrackingSession {
    var startDate: Date
    var endDate: Date
    var appName: String
    var bundleIdentifier: String?
    var domain: String?
    var filePath: String?
    var sourceRaw: String?
    var project: Project?

    init(
        startDate: Date,
        endDate: Date,
        appName: String,
        bundleIdentifier: String?,
        domain: String?,
        filePath: String?,
        source: TrackingSessionSource = .automatic,
        project: Project?,
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.domain = domain
        self.filePath = filePath
        sourceRaw = source.rawValue
        self.project = project
    }
}

extension TrackingSession {
    var source: TrackingSessionSource {
        get { TrackingSessionSource(rawValue: sourceRaw ?? "") ?? .automatic }
        set { sourceRaw = newValue.rawValue }
    }

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    var interval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }

    var sourceLabel: String {
        if let filePath {
            return filePath.filePathDisplayName
        }
        if let domain {
            return domain
        }
        return bundleIdentifier ?? appName
    }

    var contextKey: String {
        if let filePath {
            let normalized = filePath.normalizedFilePath.lowercased()
            return "file::\(normalized)"
        }
        if let domain {
            return "domain::\(domain.lowercased())"
        }
        if let bundleIdentifier {
            return "bundle::\(bundleIdentifier)"
        }
        return "app::\(appName)"
    }

    var primaryContextLabel: String {
        if let filePath {
            return filePath.filePathDisplayName
        }
        return domain ?? appName
    }

    var secondaryContextLabel: String? {
        if filePath != nil {
            return appName
        }
        return domain == nil ? nil : appName
    }

    func duration(in interval: DateInterval) -> TimeInterval {
        guard let overlap = self.interval.intersection(with: interval) else {
            return 0
        }
        return overlap.duration
    }
}
