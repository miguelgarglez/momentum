//
//  ActivityTracker.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftData
import OSLog
import Combine

#if os(macOS)
import AppKit
import IOKit

@MainActor
final class ActivityTracker: ObservableObject {
    struct StatusSummary: Equatable {
        enum State: Equatable {
            case inactive
            case tracking
            case pausedManual
            case pausedIdle
        }

        var state: State
        var appName: String?
        var domain: String?
        var projectName: String?
        var projectID: PersistentIdentifier?
    }

    @Published private(set) var isTrackingEnabled = true
    @Published private(set) var statusSummary = StatusSummary(state: .inactive)

    private let modelContainer: ModelContainer
    private let settings: TrackerSettings
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "ActivityTracker")
    private let domainResolver = BrowserDomainResolver()
    /// Interval for periodic session flushing even when the active app does not change.
    private let heartbeatInterval: TimeInterval = 60
    /// Sessions shorter than this are discarded to avoid noisy data.
    private let minimumSessionDuration: TimeInterval = 10
    /// Frequency for checking the system idle timer (seconds).
    private let idleCheckInterval: TimeInterval = 5

    private var currentContext: AppSessionContext?
    private var observer: NSObjectProtocol?
    private var heartbeatTimer: Timer?
    private var domainTimer: Timer?
    private var idleTimer: Timer?
    private var isResolvingDomain = false
    private var isUserIdle = false
    private var idleBeganAt: Date?
    private var cancellables: Set<AnyCancellable> = []

    init(modelContainer: ModelContainer, settings: TrackerSettings) {
        self.modelContainer = modelContainer
        self.settings = settings
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
        startIdleMonitoring()
        observeSettings()
        refreshStatusSummary()
    }

    deinit {
        MainActor.assumeIsolated {
            tearDown()
        }
    }

    func toggleTracking() {
        isTrackingEnabled.toggle()
        logger.info("Tracking toggled. Enabled: \(self.isTrackingEnabled, privacy: .public)")
        if isTrackingEnabled {
            restartTimersIfNeeded()
            handleAppChange(NSWorkspace.shared.frontmostApplication)
        } else {
            _ = flushCurrentSession()
            pauseTimers()
        }
        refreshStatusSummary()
    }

    private func handleAppChange(_ application: NSRunningApplication?) {
        _ = flushCurrentSession()
        guard isTrackingEnabled, let application else {
            setCurrentContext(nil)
            logger.debug("Tracking paused or no active app.")
            return
        }
        let identifier = application.bundleIdentifier ?? application.localizedName ?? "unknown"
        logger.debug("Active app is now \(identifier, privacy: .public)")
        var context = AppSessionContext(
            appName: application.localizedName ?? "App",
            bundleIdentifier: application.bundleIdentifier,
            domain: nil,
            startDate: .now,
            projectID: nil,
            projectName: nil
        )
        updateProjectAssociation(for: &context)
        setCurrentContext(context)
        if settings.isDomainTrackingEnabled {
            triggerDomainResolution()
        }
    }

    @discardableResult
    private func flushCurrentSession() -> (AppSessionContext, Date)? {
        guard var context = currentContext else { return nil }
        let endDate = Date()
        if endDate.timeIntervalSince(context.startDate) < minimumSessionDuration {
            context.startDate = endDate
            setCurrentContext(context)
            return nil
        }
        let identifier = context.bundleIdentifier ?? context.appName
        logger.debug("Closing session for \(identifier, privacy: .public)")
        persistSession(context: context, endDate: endDate)
        setCurrentContext(nil)
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
        let descriptor = FetchDescriptor<Project>(
            sortBy: [
                SortDescriptor(\Project.priority, order: .reverse),
                SortDescriptor(\Project.createdAt, order: .forward)
            ]
        )
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
        heartbeatTimer?.invalidate()
        guard isTrackingEnabled else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.debug("Heartbeat flush triggered")
                guard let (context, endDate) = self.flushCurrentSession() else { return }
                self.setCurrentContext(AppSessionContext(
                    appName: context.appName,
                    bundleIdentifier: context.bundleIdentifier,
                    domain: context.domain,
                    startDate: endDate,
                    projectID: context.projectID,
                    projectName: context.projectName
                ))
            }
        }
    }

    private func startDomainPolling() {
        domainTimer?.invalidate()
        guard isTrackingEnabled, settings.isDomainTrackingEnabled else { return }
        let interval = max(TrackerSettings.minDetectionInterval, settings.detectionInterval)
        domainTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.triggerDomainResolution()
            }
        }
    }

    private func triggerDomainResolution() {
        guard !isResolvingDomain else { return }
        guard isTrackingEnabled,
              settings.isDomainTrackingEnabled,
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
    
    private func observeSettings() {
        settings.$detectionInterval
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.startDomainPolling()
            }
            .store(in: &cancellables)

        settings.$isDomainTrackingEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    self.startDomainPolling()
                    self.triggerDomainResolution()
                } else {
                    self.domainTimer?.invalidate()
                    self.domainTimer = nil
                    if var context = self.currentContext {
                        context.domain = nil
                        self.updateProjectAssociation(for: &context)
                        self.setCurrentContext(context)
                    }
                }
            }
            .store(in: &cancellables)

        settings.$idleThreshold
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateIdleState()
            }
            .store(in: &cancellables)
    }

    private func applyResolvedDomain(_ domain: String?, for application: NSRunningApplication) {
        guard isTrackingEnabled,
              let domain,
              var context = currentContext else { return }
        guard context.bundleIdentifier == application.bundleIdentifier else { return }

        if context.domain == nil {
            context.domain = domain
            updateProjectAssociation(for: &context)
            setCurrentContext(context)
            logger.debug("Detected domain for \(context.appName, privacy: .public): \(domain, privacy: .public)")
            return
        }

        guard context.domain != domain else { return }

        logger.debug("Detected domain change for \(context.appName, privacy: .public) -> \(domain, privacy: .public)")
        if let (previousContext, endDate) = flushCurrentSession() {
            setCurrentContext(AppSessionContext(
                appName: previousContext.appName,
                bundleIdentifier: previousContext.bundleIdentifier,
                domain: domain,
                startDate: endDate,
                projectID: previousContext.projectID,
                projectName: previousContext.projectName
            ))
        } else if var current = currentContext {
            current.domain = domain
            updateProjectAssociation(for: &current)
            setCurrentContext(current)
        }
    }

    private func tearDown() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        pauseTimers()
    }

    private func startIdleMonitoring() {
        idleTimer?.invalidate()
        evaluateIdleState()
        guard isTrackingEnabled else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateIdleState()
            }
        }
    }

    private func evaluateIdleState() {
        guard isTrackingEnabled else {
            if isUserIdle {
                logger.debug("Idle monitoring reset because tracking paused")
            }
            isUserIdle = false
            idleBeganAt = nil
            refreshStatusSummary()
            return
        }
        guard let idleSeconds = systemIdleTime(), idleSeconds.isFinite else { return }
        let threshold = settings.idleThreshold
        let hasReachedIdle = idleSeconds >= threshold

        if hasReachedIdle && !isUserIdle {
            isUserIdle = true
            idleBeganAt = Date()
            logger.notice("User became idle after \(idleSeconds, privacy: .public)s (threshold \(threshold, privacy: .public)s)")
            _ = flushCurrentSession()
            setCurrentContext(nil)
            refreshStatusSummary()
            return
        }

        if !hasReachedIdle && isUserIdle {
            let idleDuration = idleBeganAt.map { Date().timeIntervalSince($0) } ?? 0
            isUserIdle = false
            idleBeganAt = nil
            logger.notice("User activity resumed after \(idleDuration, privacy: .public)s idle")
            handleAppChange(NSWorkspace.shared.frontmostApplication)
            refreshStatusSummary()
        }
    }

    private func systemIdleTime() -> TimeInterval? {
        guard let matcher = IOServiceMatching("IOHIDSystem") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matcher)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let unmanagedIdle = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }

        let idleNumber = unmanagedIdle.takeRetainedValue() as? NSNumber
        guard let idleNanoseconds = idleNumber?.uint64Value else { return nil }
        return TimeInterval(idleNanoseconds) / 1_000_000_000
    }

    private func refreshStatusSummary() {
        if !isTrackingEnabled {
            statusSummary = StatusSummary(state: .pausedManual)
            return
        }
        if isUserIdle {
            statusSummary = StatusSummary(state: .pausedIdle)
            return
        }
        guard let context = currentContext else {
            statusSummary = StatusSummary(state: .inactive)
            return
        }
        statusSummary = StatusSummary(
            state: .tracking,
            appName: context.appName,
            domain: context.domain,
            projectName: context.projectName,
            projectID: context.projectID
        )
    }

    private func setCurrentContext(_ context: AppSessionContext?) {
        currentContext = context
        refreshStatusSummary()
    }

    private func updateProjectAssociation(for context: inout AppSessionContext) {
        let info = resolveProjectInfo(for: context.bundleIdentifier, domain: context.domain)
        context.projectID = info.id
        context.projectName = info.name
    }

    private func resolveProjectInfo(for bundleIdentifier: String?, domain: String?) -> (id: PersistentIdentifier?, name: String?) {
        guard let project = resolveProject(for: bundleIdentifier, domain: domain) else {
            return (nil, nil)
        }
        return (project.persistentModelID, project.name)
    }

    private func pauseTimers() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        domainTimer?.invalidate()
        domainTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func restartTimersIfNeeded() {
        guard isTrackingEnabled else { return }
        startHeartbeat()
        startDomainPolling()
        startIdleMonitoring()
    }
}

private struct AppSessionContext {
    var appName: String
    var bundleIdentifier: String?
    var domain: String?
    var startDate: Date
    var projectID: PersistentIdentifier?
    var projectName: String?
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
