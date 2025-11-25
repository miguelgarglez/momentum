//
//  ActivityTracker.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftData
import OSLog

#if os(macOS)
import AppKit

@MainActor
final class ActivityTracker: ObservableObject {
    @Published private(set) var isTrackingEnabled = true

    private let modelContainer: ModelContainer
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "ActivityTracker")
    private let domainResolver = BrowserDomainResolver()
    private let heartbeatInterval: TimeInterval = 60
    private let domainPollingInterval: TimeInterval = 5
    private let minimumSessionDuration: TimeInterval = 10

    private var currentContext: AppSessionContext?
    private var observer: NSObjectProtocol?
    private var heartbeatTimer: Timer?
    private var domainTimer: Timer?
    private var isResolvingDomain = false

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.handleAppChange(app)
            }
        }
        handleAppChange(NSWorkspace.shared.frontmostApplication)
        startHeartbeat()
        startDomainPolling()
    }

    deinit {
        MainActor.assumeIsolated {
            self.tearDown()
        }
    }

    func toggleTracking() {
        isTrackingEnabled.toggle()
        logger.info("Tracking toggled. Enabled: \(self.isTrackingEnabled, privacy: .public)")
        if isTrackingEnabled {
            handleAppChange(NSWorkspace.shared.frontmostApplication)
        } else {
            _ = flushCurrentSession()
        }
    }

    private func handleAppChange(_ application: NSRunningApplication?) {
        _ = flushCurrentSession()
        guard isTrackingEnabled, let application else {
            currentContext = nil
            logger.debug("Tracking paused or no active app.")
            return
        }
        let identifier = application.bundleIdentifier ?? application.localizedName ?? "unknown"
        logger.debug("Active app is now \(identifier, privacy: .public)")
        currentContext = AppSessionContext(
            appName: application.localizedName ?? "App",
            bundleIdentifier: application.bundleIdentifier,
            domain: nil,
            startDate: .now
        )
        triggerDomainResolution()
    }

    @discardableResult
    private func flushCurrentSession() -> (AppSessionContext, Date)? {
        guard var context = currentContext else { return nil }
        let endDate = Date()
        if endDate.timeIntervalSince(context.startDate) < minimumSessionDuration {
            context.startDate = endDate
            currentContext = context
            return nil
        }
        let identifier = context.bundleIdentifier ?? context.appName
        logger.debug("Closing session for \(identifier, privacy: .public)")
        persistSession(context: context, endDate: endDate)
        currentContext = nil
        return (context, endDate)
    }

    private func persistSession(context: AppSessionContext, endDate: Date) {
        let session = TrackingSession(
            startDate: context.startDate,
            endDate: endDate,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            domain: context.domain,
            project: resolveProject(for: context.bundleIdentifier, domain: context.domain)
        )
        modelContainer.mainContext.insert(session)
        do {
            try modelContainer.mainContext.save()
            let projectName = session.project?.name ?? "none"
            logger.info("Logged \(session.duration, privacy: .public)s for \(session.appName, privacy: .public) project=\(projectName, privacy: .public)")
        } catch {
            logger.error("Failed to save session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func resolveProject(for bundleIdentifier: String?, domain: String?) -> Project? {
        let descriptor = FetchDescriptor<Project>()
        guard let projects = try? modelContainer.mainContext.fetch(descriptor) else {
            return nil
        }

        if let domain,
           let match = projects.first(where: { $0.matches(domain: domain) }) {
            return match
        }

        if let bundleIdentifier,
           let match = projects.first(where: { $0.matches(appBundleIdentifier: bundleIdentifier) }) {
            return match
        }

        return nil
    }

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.logger.debug("Heartbeat flush triggered")
            guard let (context, endDate) = self.flushCurrentSession() else { return }
            self.currentContext = AppSessionContext(
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                domain: context.domain,
                startDate: endDate
            )
        }
    }

    private func startDomainPolling() {
        domainTimer = Timer.scheduledTimer(withTimeInterval: domainPollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.triggerDomainResolution()
        }
    }

    private func triggerDomainResolution() {
        guard !isResolvingDomain else { return }
        guard isTrackingEnabled,
              let context = currentContext,
              domainResolver.supports(bundleIdentifier: context.bundleIdentifier) else { return }
        guard let application = NSWorkspace.shared.frontmostApplication,
              !application.isTerminated,
              application.isFinishedLaunching,
              application.bundleIdentifier == context.bundleIdentifier else { return }

        isResolvingDomain = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolvedDomain = await self.domainResolver.resolveDomain(for: application)
            self.isResolvingDomain = false
            self.applyResolvedDomain(resolvedDomain, for: application)
        }
    }

    private func applyResolvedDomain(_ domain: String?, for application: NSRunningApplication) {
        guard isTrackingEnabled,
              let domain,
              var context = currentContext else { return }
        guard context.bundleIdentifier == application.bundleIdentifier else { return }

        if context.domain == nil {
            context.domain = domain
            currentContext = context
            logger.debug("Detected domain for \(context.appName, privacy: .public): \(domain, privacy: .public)")
            return
        }

        guard context.domain != domain else { return }

        logger.debug("Detected domain change for \(context.appName, privacy: .public) -> \(domain, privacy: .public)")
        if let (previousContext, endDate) = flushCurrentSession() {
            currentContext = AppSessionContext(
                appName: previousContext.appName,
                bundleIdentifier: previousContext.bundleIdentifier,
                domain: domain,
                startDate: endDate
            )
        } else if var current = currentContext {
            current.domain = domain
            currentContext = current
        }
    }

    private func tearDown() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        domainTimer?.invalidate()
        domainTimer = nil
    }
}

private struct AppSessionContext {
    var appName: String
    var bundleIdentifier: String?
    var domain: String?
    var startDate: Date
}

private final class BrowserDomainResolver {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "BrowserDomainResolver")

    func supports(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return BrowserFamily(bundleIdentifier: bundleIdentifier) != nil
    }

    func resolveDomain(for application: NSRunningApplication) async -> String? {
        guard let identifier = application.bundleIdentifier,
              let browser = BrowserFamily(bundleIdentifier: identifier) else {
            return nil
        }

        return await Task.detached(priority: .utility) { [logger] in
            let domain = browser.fetchCurrentURLDomain(logger: logger)
            if let domain {
                logger.debug("Resolved browser domain: \(domain, privacy: .public)")
            } else {
                logger.debug("Browser domain resolution returned empty result")
            }
            return domain
        }.value
    }

    private enum BrowserFamily {
        case safari(bundleIdentifier: String)
        case chrome(bundleIdentifier: String)

        var identifier: String {
            switch self {
            case let .safari(bundleIdentifier), let .chrome(bundleIdentifier):
                return bundleIdentifier
            }
        }

        init?(bundleIdentifier: String) {
            switch bundleIdentifier {
            case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
                self = .safari(bundleIdentifier: bundleIdentifier)
            case "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta", "com.google.Chrome.dev":
                self = .chrome(bundleIdentifier: bundleIdentifier)
            default:
                return nil
            }
        }

        func fetchCurrentURLDomain(logger: Logger) -> String? {
            let script: String
            switch self {
            case let .safari(bundleIdentifier):
                script = BrowserFamily.safariScript(bundleIdentifier: bundleIdentifier)
            case let .chrome(bundleIdentifier):
                script = BrowserFamily.chromeScript(bundleIdentifier: bundleIdentifier)
            }
            guard let appleScript = NSAppleScript(source: script) else {
                logger.error("Failed to compile AppleScript for browser domain lookup")
                return nil
            }
            var error: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&error)
            if let error,
               let errorNumber = error[NSAppleScript.errorNumber] as? Int,
               errorNumber == -600 {
                logger.debug("Browser \(identifier, privacy: .public) not ready for AppleScript (not running)")
                return nil
            } else if let error {
                logger.error("AppleScript error: \(error, privacy: .public)")
            }
            guard let urlString = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty,
                  let domain = BrowserFamily.domain(from: urlString) else {
                return nil
            }
            return domain
        }

        private static func safariScript(bundleIdentifier: String) -> String {
            """
            tell application id "\(bundleIdentifier)"
                if (count of windows) = 0 then return ""
                set currentWindow to front window
                if currentWindow exists then
                    set currentTab to current tab of currentWindow
                    if currentTab exists then
                        set theURL to URL of currentTab
                        return theURL
                    end if
                end if
            end tell
            return ""
            """
        }

        private static func chromeScript(bundleIdentifier: String) -> String {
            """
            tell application id "\(bundleIdentifier)"
                if (count of windows) = 0 then return ""
                set currentWindow to front window
                if currentWindow exists then
                    set currentTab to active tab of currentWindow
                    if currentTab exists then
                        set theURL to URL of currentTab
                        return theURL
                    end if
                end if
            end tell
            return ""
            """
        }

        private static func domain(from urlString: String) -> String? {
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var normalized = trimmed
            if !normalized.contains("://") {
                normalized = "https://\(normalized)"
            }
            guard let url = URL(string: normalized),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  var host = url.host?.lowercased() else {
                return nil
            }
            if host.hasPrefix("www.") {
                host.removeFirst(4)
            }
            return host
        }
    }
}
#else
/// Placeholder implementation so previews build on other platforms.
final class ActivityTracker: ObservableObject {
    init(modelContainer: ModelContainer) {}
    func toggleTracking() {}
}
#endif
