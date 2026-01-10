//
//  PendingTrackingSession.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftData

@Model
final class PendingTrackingSession {
    var startDate: Date
    var endDate: Date
    var appName: String
    var bundleIdentifier: String?
    var domain: String?
    var filePath: String?
    var contextType: String
    var contextValue: String

    init(
        startDate: Date,
        endDate: Date,
        appName: String,
        bundleIdentifier: String?,
        domain: String?,
        filePath: String?,
        contextType: String,
        contextValue: String,
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.domain = domain
        self.filePath = filePath
        self.contextType = contextType
        self.contextValue = contextValue
    }
}
