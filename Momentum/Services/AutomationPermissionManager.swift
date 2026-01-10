//
//  AutomationPermissionManager.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
#if os(macOS)
    import AppKit
    import ApplicationServices
#endif

@MainActor
final class AutomationPermissionManager: ObservableObject {
    @Published private(set) var isTrusted: Bool = true

    init() {
        #if os(macOS)
            isTrusted = hasAutomationPermission()
        #else
            isTrusted = true
        #endif
    }

    func refresh() {
        #if os(macOS)
            isTrusted = hasAutomationPermission()
        #else
            isTrusted = true
        #endif
    }

    #if os(macOS)
        func requestAutomationPermissions(for bundleIdentifiers: Set<String>) {
            let installedTargets = bundleIdentifiers.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
            installedTargets.forEach { _ = isAutomationAllowed(for: $0, prompt: true) }
            refresh()
        }

        func openSystemSettings() {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
                return
            }
            NSWorkspace.shared.open(url)
        }

        private func hasAutomationPermission() -> Bool {
            let installedTargets = Self.automationBundleIdentifiers.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
            guard !installedTargets.isEmpty else {
                return true
            }
            return installedTargets.contains { isAutomationAllowed(for: $0) }
        }

        private func isAutomationAllowed(for bundleIdentifier: String, prompt: Bool = false) -> Bool {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(
                target.aeDesc,
                AEEventClass(kAECoreSuite),
                AEEventID(kAEGetData),
                prompt,
            )
            return status == noErr
        }
    #endif

    static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
    ]

    static let documentBundleIdentifiers: Set<String> = [
        "com.apple.Preview",
        "com.microsoft.Word",
        "com.microsoft.Powerpoint",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Keynote",
        "com.apple.iWork.Numbers",
    ]

    static let automationBundleIdentifiers: Set<String> = browserBundleIdentifiers.union(documentBundleIdentifiers)
}
