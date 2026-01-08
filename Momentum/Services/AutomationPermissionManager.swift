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
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func hasAutomationPermission() -> Bool {
        let installedBrowsers = Self.browserBundleIdentifiers.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        guard !installedBrowsers.isEmpty else {
            return true
        }
        return installedBrowsers.contains { isAutomationAllowed(for: $0) }
    }

    private func isAutomationAllowed(for bundleIdentifier: String) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            AEEventClass(kAECoreSuite),
            AEEventID(kAEGetData),
            false
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
        "com.google.Chrome.dev"
    ]
}
