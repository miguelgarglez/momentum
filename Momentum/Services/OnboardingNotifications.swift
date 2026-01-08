//
//  OnboardingNotifications.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation

extension Notification.Name {
    static let onboardingProjectCreated = Notification.Name("OnboardingProjectCreated")
}

enum OnboardingUserInfoKey {
    static let projectID = "OnboardingProjectID"
    static let startTracking = "OnboardingStartTracking"
}
