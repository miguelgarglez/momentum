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

/// Central coordinator for activity tracking in Momentum.
///
/// `ActivityTracker` listens to workspace activation notifications, creates and
/// flushes app sessions, resolves browser domains, and routes each session to
/// the appropriate project. It also integrates with cross‑cutting concerns:
/// - `PerformanceBudgetMonitoring` to measure and constrain the cost of tracking
/// - `CrashRecoveryHandling` to snapshot and replay in‑flight sessions after a crash
/// - `ProjectAssignmentResolving` to map bundle identifiers and domains to projects
///
/// The tracker is designed to be testable via dependency injection and debug‑only
/// helpers, so its behavior can be validated in isolation from the UI and storage.
@MainActor
final class ActivityTracker: ObservableObject {
    struct StatusSummary: Equatable {
        enum State: Equatable {
            case inactive
            case tracking
            case pausedManual
            case pausedIdle
            case pausedScreenLocked
            case pausedExcluded
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
    private let crashRecovery: CrashRecoveryHandling
    private let performanceMonitor: PerformanceBudgetMonitoring
    private let assignmentResolver: ProjectAssignmentResolving
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
    private var screenLockObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var isResolvingDomain = false
    private var isUserIdle = false
    private var isScreenLocked = false
    private var idleBeganAt: Date?
    private var cancellables: Set<AnyCancellable> = []

    init(
        modelContainer: ModelContainer,
        settings: TrackerSettings,
        crashRecovery: CrashRecoveryHandling? = nil,
        performanceMonitor: PerformanceBudgetMonitoring? = nil,
        assignmentResolver: ProjectAssignmentResolving? = nil
    ) {
        self.modelContainer = modelContainer
        self.settings = settings
        self.crashRecovery = crashRecovery ?? CrashRecoveryManager()
        self.performanceMonitor = performanceMonitor ?? PerformanceBudgetMonitor()
        self.assignmentResolver = assignmentResolver ?? ProjectAssignmentResolver(modelContainer: modelContainer)
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
        startScreenLockMonitoring()
        observeSettings()
        refreshStatusSummary()
        recoverLastSessionIfNeeded()
    }

    deinit {
        MainActor.assumeIsolated {
            tearDown()
        }
    }

    private func recoverLastSessionIfNeeded() {
        guard let snapshot = crashRecovery.consumePendingSnapshot(),
              !snapshot.isExcluded else { return }
        var context = AppSessionContext(
            appName: snapshot.appName,
            bundleIdentifier: snapshot.bundleIdentifier,
            domain: snapshot.domain,
            startDate: snapshot.startDate,
            projectID: nil,
            projectName: snapshot.projectName,
            isExcluded: snapshot.isExcluded
        )
        updateProjectAssociation(for: &context)
        let endDate = Date()
        performanceMonitor.measure("session.recover") {
            persistSession(context: context, endDate: endDate)
        }
        logger.notice("Recovered session after crash. Duration: \(endDate.timeIntervalSince(context.startDate), privacy: .public)s")
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
        let isExcludedApp = settings.isAppExcluded(application.bundleIdentifier)
        var context = AppSessionContext(
            appName: application.localizedName ?? "App",
            bundleIdentifier: application.bundleIdentifier,
            domain: nil,
            startDate: .now,
            projectID: nil,
            projectName: nil,
            isExcluded: isExcludedApp
        )
        if !isExcludedApp {
            updateProjectAssociation(for: &context)
        } else {
            logger.debug("App \(identifier, privacy: .public) is excluded from tracking")
        }
        setCurrentContext(context)
        if settings.isDomainTrackingEnabled, !isExcludedApp {
            triggerDomainResolution()
        }
    }

    @discardableResult
    private func flushCurrentSession() -> (AppSessionContext, Date)? {
        guard var context = currentContext else { return nil }
        let endDate = Date()
        if context.isExcluded {
            setCurrentContext(nil)
            return (context, endDate)
        }
        if endDate.timeIntervalSince(context.startDate) < minimumSessionDuration {
            context.startDate = endDate
            setCurrentContext(context)
            return nil
        }
        let identifier = context.bundleIdentifier ?? context.appName
        logger.debug("Closing session for \(identifier, privacy: .public)")
        performanceMonitor.measure("session.persist") {
            persistSession(context: context, endDate: endDate)
        }
        setCurrentContext(nil)
        return (context, endDate)
    }

    private func persistSession(context: AppSessionContext, endDate: Date) {
        guard endDate > context.startDate else { return }
        guard let project = assignmentResolver.resolveProject(for: context.bundleIdentifier, domain: context.domain) else {
            logger.debug("Skipping session for \(context.bundleIdentifier ?? context.appName, privacy: .public) - no project matches")
            return
        }
        let interval = DateInterval(start: context.startDate, end: endDate)
        let overlapResolver = SessionOverlapResolver(context: modelContainer.mainContext)
        let removedSegments = overlapResolver.resolveOverlaps(with: interval)
        let session = TrackingSession(
            startDate: context.startDate,
            endDate: endDate,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            domain: context.domain,
            project: project
        )
        modelContainer.mainContext.insert(session)
        removedSegments.forEach { project, removedInterval in
            updateDailySummaries(for: project, interval: removedInterval, sign: -1)
        }
        updateDailySummaries(for: project, interval: interval, sign: 1)
        do {
            try modelContainer.mainContext.save()
            let projectName = session.project?.name ?? "none"
            logger.info("Logged \(session.duration, privacy: .public)s for \(session.appName, privacy: .public) project=\(projectName, privacy: .public)")
        } catch {
            logger.error("Failed to save session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateDailySummaries(for project: Project?, interval: DateInterval, sign: Double) {
        guard let project, interval.duration > 0, sign != 0 else { return }
        var cursor = DailySummary.normalize(interval.start)
        let calendar = Calendar.current
        while cursor < interval.end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let dayInterval = DateInterval(start: cursor, end: nextDay)
            if let overlap = interval.intersection(with: dayInterval) {
                applyDailySummaryDelta(project: project, day: cursor, deltaSeconds: overlap.duration * sign)
            }
            cursor = nextDay
        }
    }

    private func applyDailySummaryDelta(project: Project, day: Date, deltaSeconds: TimeInterval) {
        guard deltaSeconds != 0 else { return }
        let normalizedDay = DailySummary.normalize(day)
        if let summary = project.dailySummaries.first(where: { $0.date == normalizedDay }) {
            summary.apply(deltaSeconds: deltaSeconds)
            if summary.seconds <= 0 {
                modelContainer.mainContext.delete(summary)
            }
            return
        }
        guard deltaSeconds > 0 else { return }
        let summary = DailySummary(date: normalizedDay, seconds: deltaSeconds, project: project)
        modelContainer.mainContext.insert(summary)
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
                    projectName: context.projectName,
                    isExcluded: context.isExcluded
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
              !context.isExcluded,
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
                        if !context.isExcluded {
                            self.updateProjectAssociation(for: &context)
                        }
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

        settings.$excludedApps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.enforceExclusionRules()
            }
            .store(in: &cancellables)

        settings.$excludedDomains
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.enforceExclusionRules()
            }
            .store(in: &cancellables)
    }

    private func applyResolvedDomain(_ domain: String?, for application: NSRunningApplication) {
        guard isTrackingEnabled,
              let domain,
              var context = currentContext else { return }
        guard context.bundleIdentifier == application.bundleIdentifier else { return }

        if settings.isDomainExcluded(domain) {
            logger.debug("Domain \(domain, privacy: .public) marked as excluded. Suspending tracking.")
            let source = context
            if let (_, endDate) = flushCurrentSession() {
                let excludedContext = AppSessionContext(
                    appName: source.appName,
                    bundleIdentifier: source.bundleIdentifier,
                    domain: domain,
                    startDate: endDate,
                    projectID: nil,
                    projectName: nil,
                    isExcluded: true
                )
                setCurrentContext(excludedContext)
            } else if var current = currentContext {
                current.domain = domain
                current.isExcluded = true
                current.projectID = nil
                current.projectName = nil
                current.startDate = .now
                setCurrentContext(current)
            } else {
                let excludedContext = AppSessionContext(
                    appName: source.appName,
                    bundleIdentifier: source.bundleIdentifier,
                    domain: domain,
                    startDate: .now,
                    projectID: nil,
                    projectName: nil,
                    isExcluded: true
                )
                setCurrentContext(excludedContext)
            }
            return
        }

        if context.isExcluded {
            logger.debug("Domain \(domain, privacy: .public) is allowed again. Resuming tracking.")
            let source = context
            if let (_, endDate) = flushCurrentSession() {
                var resumed = AppSessionContext(
                    appName: source.appName,
                    bundleIdentifier: source.bundleIdentifier,
                    domain: domain,
                    startDate: endDate,
                    projectID: nil,
                    projectName: nil,
                    isExcluded: false
                )
                updateProjectAssociation(for: &resumed)
                setCurrentContext(resumed)
            } else if var current = currentContext {
                current.domain = domain
                current.isExcluded = false
                current.startDate = .now
                updateProjectAssociation(for: &current)
                setCurrentContext(current)
            } else {
                var resumed = AppSessionContext(
                    appName: source.appName,
                    bundleIdentifier: source.bundleIdentifier,
                    domain: domain,
                    startDate: .now,
                    projectID: nil,
                    projectName: nil,
                    isExcluded: false
                )
                updateProjectAssociation(for: &resumed)
                setCurrentContext(resumed)
            }
            return
        }

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
                projectName: previousContext.projectName,
                isExcluded: previousContext.isExcluded
            ))
        } else if var current = currentContext {
            current.domain = domain
            if !current.isExcluded {
                updateProjectAssociation(for: &current)
            }
            setCurrentContext(current)
        }
    }

    private func enforceExclusionRules() {
        guard let context = currentContext else { return }
        let shouldExclude = settings.isAppExcluded(context.bundleIdentifier) || settings.isDomainExcluded(context.domain)
        if shouldExclude && !context.isExcluded {
            logger.debug("Current context became excluded after settings update")
            let source = context
            if let (_, endDate) = flushCurrentSession() {
                let excludedContext = AppSessionContext(
                    appName: source.appName,
                    bundleIdentifier: source.bundleIdentifier,
                    domain: source.domain,
                    startDate: endDate,
                    projectID: nil,
                    projectName: nil,
                    isExcluded: true
                )
                setCurrentContext(excludedContext)
            } else if var current = currentContext {
                current.isExcluded = true
                current.projectID = nil
                current.projectName = nil
                current.startDate = .now
                setCurrentContext(current)
            }
            return
        }

        if !shouldExclude && context.isExcluded {
            logger.debug("Context is no longer excluded; resuming tracking")
            let source = context
            if let (_, endDate) = flushCurrentSession() {
                var resumed = AppSessionContext(
                    appName: source.appName,
                    bundleIdentifier: source.bundleIdentifier,
                    domain: source.domain,
                    startDate: endDate,
                    projectID: nil,
                    projectName: nil,
                    isExcluded: false
                )
                updateProjectAssociation(for: &resumed)
                setCurrentContext(resumed)
            } else if var current = currentContext {
                current.isExcluded = false
                current.startDate = .now
                updateProjectAssociation(for: &current)
                setCurrentContext(current)
            }
        }
    }

    private func tearDown() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        stopScreenLockMonitoring()
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

    private func startScreenLockMonitoring() {
        stopScreenLockMonitoring()
        let center = DistributedNotificationCenter.default()
        screenLockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenLockChange(isLocked: true)
            }
        }
        screenUnlockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenLockChange(isLocked: false)
            }
        }
    }

    private func stopScreenLockMonitoring() {
        let center = DistributedNotificationCenter.default()
        if let screenLockObserver {
            center.removeObserver(screenLockObserver)
            self.screenLockObserver = nil
        }
        if let screenUnlockObserver {
            center.removeObserver(screenUnlockObserver)
            self.screenUnlockObserver = nil
        }
    }

    private func handleScreenLockChange(isLocked: Bool) {
        guard isScreenLocked != isLocked else { return }
        isScreenLocked = isLocked
        if isLocked {
            logger.notice("Screen locked - pausing tracking")
            isUserIdle = false
            idleBeganAt = nil
            guard isTrackingEnabled else {
                refreshStatusSummary()
                return
            }
            _ = flushCurrentSession()
            setCurrentContext(nil)
            pauseTimers()
            refreshStatusSummary()
        } else {
            logger.notice("Screen unlocked - resuming tracking")
            isUserIdle = false
            idleBeganAt = nil
            guard isTrackingEnabled else {
                refreshStatusSummary()
                return
            }
            restartTimersIfNeeded()
            handleAppChange(NSWorkspace.shared.frontmostApplication)
            refreshStatusSummary()
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
        if isScreenLocked {
            statusSummary = StatusSummary(state: .pausedScreenLocked)
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
        if context.isExcluded {
            statusSummary = StatusSummary(
                state: .pausedExcluded,
                appName: context.appName,
                domain: context.domain,
                projectName: nil,
                projectID: nil
            )
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
        crashRecovery.persist(snapshot: context.map { SessionSnapshot(context: $0) })
        refreshStatusSummary()
    }

    private func updateProjectAssociation(for context: inout AppSessionContext) {
        guard let project = assignmentResolver.resolveProject(for: context.bundleIdentifier, domain: context.domain) else {
            context.projectID = nil
            context.projectName = nil
            return
        }
        context.projectID = project.persistentModelID
        context.projectName = project.name
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
    var isExcluded: Bool
}

private extension SessionSnapshot {
    init(context: AppSessionContext) {
        self.init(
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            domain: context.domain,
            startDate: context.startDate,
            projectName: context.projectName,
            isExcluded: context.isExcluded
        )
    }
}

#if DEBUG
extension ActivityTracker {
    func testing_beginContext(
        appName: String,
        bundleIdentifier: String? = nil,
        domain: String? = nil,
        startDate: Date = Date().addingTimeInterval(-20),
        isExcluded: Bool = false
    ) {
        _ = flushCurrentSession()
        var context = AppSessionContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            domain: domain,
            startDate: startDate,
            projectID: nil,
            projectName: nil,
            isExcluded: isExcluded
        )
        if !isExcluded {
            updateProjectAssociation(for: &context)
        }
        setCurrentContext(context)
    }

    func testing_forceIdleState(_ idle: Bool) {
        isUserIdle = idle
        refreshStatusSummary()
    }

    @discardableResult
    func testing_forceFlush() -> Bool {
        flushCurrentSession() != nil
    }
}
#endif

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
