//
//  OnboardingState.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation

@MainActor
final class OnboardingState: ObservableObject {
    @Published var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Keys.hasSeenWelcome) }
    }
    @Published var hasCreatedProject: Bool {
        didSet { defaults.set(hasCreatedProject, forKey: Keys.hasCreatedProject) }
    }
    @Published var hasAutomationPermissionPrompted: Bool {
        didSet { defaults.set(hasAutomationPermissionPrompted, forKey: Keys.hasAutomationPermissionPrompted) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if Self.shouldSkipOnboarding {
            defaults.set(true, forKey: Keys.hasSeenWelcome)
            defaults.set(true, forKey: Keys.hasCreatedProject)
            defaults.set(true, forKey: Keys.hasAutomationPermissionPrompted)
        }
        hasSeenWelcome = defaults.bool(forKey: Keys.hasSeenWelcome)
        hasCreatedProject = defaults.bool(forKey: Keys.hasCreatedProject)
        hasAutomationPermissionPrompted = defaults.bool(forKey: Keys.hasAutomationPermissionPrompted)
    }

    func markWelcomeSeen() {
        hasSeenWelcome = true
    }

    func markProjectCreated() {
        hasCreatedProject = true
    }

    func markAutomationPrompted() {
        hasAutomationPermissionPrompted = true
    }
}

private enum Keys {
    static let hasSeenWelcome = "Onboarding.hasSeenWelcome"
    static let hasCreatedProject = "Onboarding.hasCreatedProject"
    static let hasAutomationPermissionPrompted = "Onboarding.hasAccessibilityPermissionPrompted"
}

private extension OnboardingState {
    static var shouldSkipOnboarding: Bool {
        CommandLine.arguments.contains("--skip-onboarding")
            || ProcessInfo.processInfo.environment["MOMENTUM_SKIP_ONBOARDING"] == "1"
    }
}
