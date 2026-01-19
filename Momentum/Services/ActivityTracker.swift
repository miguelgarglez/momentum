//
//  ActivityTracker.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Combine
import Foundation
import OSLog
import SwiftData

#if os(macOS)
    @preconcurrency import AppKit
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
                case trackingManual
                case pendingResolution
                case pausedManual
                case pausedIdle
                case pausedScreenLocked
                case pausedExcluded
            }

            var state: State
            var appName: String?
            var domain: String?
            var filePath: String?
            var bundleIdentifier: String?
            var projectName: String?
            var projectID: PersistentIdentifier?
        }

        enum ManualStopReason: String, Equatable {
            case manual
            case idle
            case screenLocked
        }

        struct ManualStopEvent: Identifiable, Equatable {
            let id = UUID()
            let reason: ManualStopReason
        }

        @Published private(set) var isTrackingEnabled = true
        @Published private(set) var statusSummary = StatusSummary(state: .inactive)
        @Published private(set) var pendingConflictCount: Int = 0
        @Published private(set) var isManualTrackingActive: Bool = false
        @Published private(set) var manualStopEvent: ManualStopEvent?

        private let modelContainer: ModelContainer
        private let settings: TrackerSettings
        private let crashRecovery: CrashRecoveryHandling
        private let performanceMonitor: PerformanceBudgetMonitoring
        private let assignmentResolver: ProjectAssignmentResolving
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "ActivityTracker")
        private let domainResolver = BrowserDomainResolver()
        private let fileResolver = FileDocumentResolver()
        /// Interval for periodic session flushing even when the active app does not change.
        private let heartbeatInterval: TimeInterval = 300
        /// Sessions shorter than this are discarded to avoid noisy data.
        private let minimumSessionDuration: TimeInterval = 10
        /// Frequency for checking the system idle timer (seconds).
        private let idleCheckInterval: TimeInterval = 5
        /// Frequency for purging expired assignment rules.
        private let rulesCleanupInterval: TimeInterval = 60 * 60 * 24
        /// Max interval for domain/file polling backoff.
        private let maxResolutionInterval: TimeInterval = 60
        /// Debounce interval for coalescing SwiftData saves.
        private let saveDebounceInterval: TimeInterval = 2
        /// Maximum interval before forcing a SwiftData save.
        private let saveMaxInterval: TimeInterval = 10
        /// Safety floor for timer intervals to avoid hot loops.
        private let minimumTimerInterval: TimeInterval = 1

        private var currentContext: AppSessionContext?
        private var observer: NSObjectProtocol?
        private var heartbeatTimer: Timer?
        private var domainTimer: Timer?
        private var fileTimer: Timer?
        private var idleTimer: Timer?
        private var rulesCleanupTimer: Timer?
        private var screenLockObserver: NSObjectProtocol?
        private var screenUnlockObserver: NSObjectProtocol?
        private var isResolvingDomain = false
        private var isResolvingFile = false
        private var domainBackoffLevel = 0
        private var fileBackoffLevel = 0
        private var isUserIdle = false
        private var isScreenLocked = false
        private var idleBeganAt: Date?
        private var manualProjectID: PersistentIdentifier?
        private var manualStartDate: Date?
        private var pendingSwiftDataSave = false
        private var pendingSwiftDataSaveSince: Date?
        private var lastSwiftDataSaveRequestAt: Date?
        private var swiftDataSaveTask: Task<Void, Never>?
        private var diagnosticsReporter: DiagnosticsReporter?
        private var cancellables: Set<AnyCancellable> = []

        init(
            modelContainer: ModelContainer,
            settings: TrackerSettings,
            crashRecovery: CrashRecoveryHandling? = nil,
            performanceMonitor: PerformanceBudgetMonitoring? = nil,
            assignmentResolver: ProjectAssignmentResolving? = nil,
        ) {
            self.modelContainer = modelContainer
            self.settings = settings
            self.crashRecovery = crashRecovery ?? CrashRecoveryManager()
            self.performanceMonitor = performanceMonitor ?? PerformanceBudgetMonitor()
            self.assignmentResolver = assignmentResolver ?? ProjectAssignmentResolver(modelContainer: modelContainer, settings: settings)
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main,
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in
                    self?.handleAppChange(app)
                }
            }
            recoverLastSessionIfNeeded()
            handleAppChange(NSWorkspace.shared.frontmostApplication)
            startHeartbeat()
            startDomainPolling()
            startFilePolling()
            startIdleMonitoring()
            startScreenLockMonitoring()
            observeSettings()
            startRuleExpirationMonitoring()
            refreshStatusSummary()
            refreshPendingConflictCount()
            if Diagnostics.isEnabled {
                diagnosticsReporter = DiagnosticsReporter()
            }
        }

        deinit {
            MainActor.assumeIsolated {
                tearDown()
            }
        }

        private func recoverLastSessionIfNeeded() {
            guard !RuntimeFlags.isDisabled(.disableCrashRecovery) else { return }
            Diagnostics.record(.crashRecoveryRun) {
                guard let snapshot = crashRecovery.consumePendingSnapshot() else { return }
                if snapshot.isManualTrackingActive ?? false {
                    if let manualProject = fetchManualProject(for: snapshot.manualProjectID) {
                        isManualTrackingActive = true
                        manualProjectID = manualProject.persistentModelID
                        manualStartDate = snapshot.manualStartDate ?? snapshot.startDate
                    } else {
                        logger.notice("Manual tracking snapshot referenced missing project; skipping manual restore")
                        isManualTrackingActive = false
                        manualProjectID = nil
                        manualStartDate = nil
                    }
                }
                guard !snapshot.isExcluded else { return }
                var context = AppSessionContext(
                    appName: snapshot.appName,
                    bundleIdentifier: snapshot.bundleIdentifier,
                    domain: snapshot.domain,
                    filePath: snapshot.filePath,
                    startDate: snapshot.startDate,
                    projectID: nil,
                    projectName: snapshot.projectName,
                    isExcluded: snapshot.isExcluded,
                    isPendingAssignment: false,
                )
                if isManualTrackingActive {
                    applyManualProjectAssociation(to: &context)
                } else {
                    updateProjectAssociation(for: &context)
                }
                let endDate = Date()
                performanceMonitor.measure("session.recover") {
                    persistSession(context: context, endDate: endDate)
                }
                logger.notice("Recovered session after crash. Duration: \(endDate.timeIntervalSince(context.startDate), privacy: .public)s")
            }
        }

        func toggleTracking() {
            if isTrackingEnabled {
                if isManualTrackingActive {
                    stopManualTracking(reason: .manual, resumeAutomatically: false)
                }
                isTrackingEnabled = false
                logger.info("Tracking toggled. Enabled: \(self.isTrackingEnabled, privacy: .public)")
                _ = flushCurrentSession()
                pauseTimers()
            } else {
                isTrackingEnabled = true
                logger.info("Tracking toggled. Enabled: \(self.isTrackingEnabled, privacy: .public)")
                restartTimersIfNeeded()
                handleAppChange(NSWorkspace.shared.frontmostApplication)
            }
            refreshStatusSummary()
        }

        func refreshPendingConflicts() {
            refreshPendingConflictCount()
        }

        func startManualTracking(project: Project) {
            _ = flushCurrentSession()
            if !isTrackingEnabled {
                isTrackingEnabled = true
            }
            isManualTrackingActive = true
            manualProjectID = project.persistentModelID
            manualStartDate = Date()
            restartTimersIfNeeded()
            handleAppChange(NSWorkspace.shared.frontmostApplication)
            refreshStatusSummary()
        }

        func stopManualTracking(reason: ManualStopReason, resumeAutomatically: Bool = true) {
            guard isManualTrackingActive else { return }
            _ = flushCurrentSession()
            isManualTrackingActive = false
            manualProjectID = nil
            manualStartDate = nil
            manualStopEvent = ManualStopEvent(reason: reason)
            if resumeAutomatically {
                if isTrackingEnabled, !isUserIdle, !isScreenLocked {
                    restartTimersIfNeeded()
                    handleAppChange(NSWorkspace.shared.frontmostApplication)
                } else {
                    setCurrentContext(nil)
                }
            } else {
                setCurrentContext(nil)
            }
            refreshStatusSummary()
        }

        private func handleAppChange(_ application: NSRunningApplication?) {
            _ = flushCurrentSession()
            guard isTrackingEnabled, let application else {
                setCurrentContext(nil)
                updateResolutionPolling(for: nil)
                logger.debug("Tracking paused or no active app.")
                return
            }
            let identifier = application.bundleIdentifier ?? application.localizedName ?? "unknown"
            logger.debug("Active app is now \(identifier, privacy: .public)")
            let isExcludedApp = isManualTrackingActive ? false : settings.isAppExcluded(application.bundleIdentifier)
            var context = AppSessionContext(
                appName: application.localizedName ?? "App",
                bundleIdentifier: application.bundleIdentifier,
                domain: nil,
                filePath: nil,
                startDate: .now,
                projectID: nil,
                projectName: nil,
                isExcluded: isExcludedApp,
                isPendingAssignment: false,
            )
            if !isExcludedApp {
                updateProjectAssociation(for: &context)
            } else {
                logger.debug("App \(identifier, privacy: .public) is excluded from tracking")
            }
            setCurrentContext(context)
            updateResolutionPolling(for: context)
            resetDomainBackoff()
            resetFileBackoff()
            if settings.isDomainTrackingEnabled, !isExcludedApp {
                triggerDomainResolution()
            }
            if settings.isFileTrackingEnabled, !isExcludedApp {
                triggerFileResolution()
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
            if isManualTrackingActive {
                guard let manualProject = resolveManualProject() else { return }
                persistManualSession(context: context, endDate: endDate, project: manualProject)
                return
            }
            switch assignmentResolver.resolveAssignment(
                for: context.bundleIdentifier,
                domain: context.domain,
                filePath: context.filePath,
            ) {
            case let .assigned(project, _):
                persistSession(context: context, endDate: endDate, project: project)
            case let .conflict(conflictContext, _):
                persistPendingSession(context: context, endDate: endDate, conflictContext: conflictContext)
            case .none:
                logger.debug("Skipping session for \(context.bundleIdentifier ?? context.appName, privacy: .public) - no project matches")
            }
        }

        private func persistSession(context: AppSessionContext, endDate: Date, project: Project) {
            guard !RuntimeFlags.isDisabled(.disableSwiftDataWrites) else { return }
            insertResolvedSession(context: context, endDate: endDate, project: project)
            scheduleSwiftDataSave()
            logger.info("Logged \(endDate.timeIntervalSince(context.startDate), privacy: .public)s for \(context.appName, privacy: .public) project=\(project.name, privacy: .public)")
        }

        private func persistManualSession(context: AppSessionContext, endDate: Date, project: Project) {
            guard !RuntimeFlags.isDisabled(.disableSwiftDataWrites) else { return }
            insertResolvedSession(context: context, endDate: endDate, project: project)
            updateManualProjectAssignments(for: project, context: context)
            scheduleSwiftDataSave()
            logger.info("Logged manual \(endDate.timeIntervalSince(context.startDate), privacy: .public)s for \(context.appName, privacy: .public) project=\(project.name, privacy: .public)")
        }

        private func updateManualProjectAssignments(for project: Project, context: AppSessionContext) {
            if let bundleIdentifier = context.bundleIdentifier, !bundleIdentifier.isEmpty {
                project.addAssignedApp(bundleIdentifier)
            }
            if settings.isDomainTrackingEnabled, let domain = context.domain, !domain.isEmpty {
                project.addAssignedDomain(domain)
            }
            if settings.isFileTrackingEnabled, let filePath = context.filePath, !filePath.isEmpty {
                project.addAssignedFile(filePath)
            }
        }

        private func persistPendingSession(
            context: AppSessionContext,
            endDate: Date,
            conflictContext: AssignmentContext,
        ) {
            guard !RuntimeFlags.isDisabled(.disableSwiftDataWrites) else { return }
            let pending = PendingTrackingSession(
                startDate: context.startDate,
                endDate: endDate,
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                domain: context.domain,
                filePath: context.filePath,
                contextType: conflictContext.type.rawValue,
                contextValue: conflictContext.value,
            )
            modelContainer.mainContext.insert(pending)
            scheduleSwiftDataSave()
            refreshPendingConflictCount()
            logger.info("Stored pending session for \(conflictContext.value, privacy: .public)")
        }

        private func insertResolvedSession(
            context: AppSessionContext,
            endDate: Date,
            project: Project,
        ) {
            let interval = DateInterval(start: context.startDate, end: endDate)
            let overlapResolver = SessionOverlapResolver(context: modelContainer.mainContext)
            let removedSegments = overlapResolver.resolveOverlaps(with: interval)
            let session = TrackingSession(
                startDate: context.startDate,
                endDate: endDate,
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                domain: context.domain,
                filePath: context.filePath,
                project: project,
            )
            modelContainer.mainContext.insert(session)
            var touchedProjects: [PersistentIdentifier: Project] = [:]
            for (removedProject, removedInterval) in removedSegments {
                updateDailySummaries(for: removedProject, interval: removedInterval, sign: -1)
                guard let removedProject else { continue }
                touchedProjects[removedProject.persistentModelID] = removedProject
            }
            updateDailySummaries(for: project, interval: interval, sign: 1)
            touchedProjects[project.persistentModelID] = project
            for (_, touched) in touchedProjects {
                touched.markStatsDirty()
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
            guard isTrackingEnabled, !RuntimeFlags.isDisabled(.disableHeartbeat) else { return }
            let interval = max(heartbeatInterval, minimumTimerInterval)
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    Diagnostics.record(.heartbeatTick) {
                        self.logger.debug("Heartbeat flush triggered")
                        guard let (context, endDate) = self.flushCurrentSession() else { return }
                        self.setCurrentContext(AppSessionContext(
                            appName: context.appName,
                            bundleIdentifier: context.bundleIdentifier,
                            domain: context.domain,
                            filePath: context.filePath,
                            startDate: endDate,
                            projectID: context.projectID,
                            projectName: context.projectName,
                            isExcluded: context.isExcluded,
                            isPendingAssignment: context.isPendingAssignment,
                        ))
                    }
                }
            }
            timer.tolerance = interval * 0.1
            heartbeatTimer = timer
        }

        private func startDomainPolling() {
            domainTimer?.invalidate()
            guard isTrackingEnabled, settings.isDomainTrackingEnabled else { return }
            let interval = domainPollingInterval()
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.triggerDomainResolution()
                }
            }
            timer.tolerance = interval * 0.1
            domainTimer = timer
        }

        private func startFilePolling() {
            fileTimer?.invalidate()
            guard isTrackingEnabled, settings.isFileTrackingEnabled else { return }
            let interval = filePollingInterval()
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.triggerFileResolution()
                }
            }
            timer.tolerance = interval * 0.1
            fileTimer = timer
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
            let previousDomain = currentContext?.domain
            let previousExcluded = currentContext?.isExcluded ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                let resolvedDomain = await self.domainResolver.resolveDomain(for: application)
                self.isResolvingDomain = false
                self.applyResolvedDomain(resolvedDomain, for: application)
                let didChange = previousDomain != self.currentContext?.domain ||
                    previousExcluded != (self.currentContext?.isExcluded ?? false)
                if didChange {
                    self.resetDomainBackoff()
                } else {
                    self.bumpDomainBackoffIfNeeded()
                }
            }
        }

        private func triggerFileResolution() {
            guard !isResolvingFile else { return }
            guard isTrackingEnabled,
                  settings.isFileTrackingEnabled,
                  let context = currentContext,
                  !context.isExcluded,
                  fileResolver.supports(bundleIdentifier: context.bundleIdentifier) else { return }
            guard let application = NSWorkspace.shared.frontmostApplication,
                  !application.isTerminated,
                  application.isFinishedLaunching,
                  application.bundleIdentifier == context.bundleIdentifier else { return }

            isResolvingFile = true
            let previousFile = currentContext?.filePath
            let previousExcluded = currentContext?.isExcluded ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                let resolvedPath = await self.fileResolver.resolveFilePath(for: application)
                self.isResolvingFile = false
                self.applyResolvedFilePath(resolvedPath, for: application)
                let didChange = previousFile != self.currentContext?.filePath ||
                    previousExcluded != (self.currentContext?.isExcluded ?? false)
                if didChange {
                    self.resetFileBackoff()
                } else {
                    self.bumpFileBackoffIfNeeded()
                }
            }
        }

        private func observeSettings() {
            settings.$detectionInterval
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.resetDomainBackoff()
                    self?.resetFileBackoff()
                }
                .store(in: &cancellables)

            settings.$isDomainTrackingEnabled
                .receive(on: RunLoop.main)
                .sink { [weak self] isEnabled in
                    guard let self else { return }
                    if isEnabled {
                        self.resetDomainBackoff()
                        self.triggerDomainResolution()
                    } else {
                        self.stopDomainPolling()
                        self.domainBackoffLevel = 0
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

            settings.$isFileTrackingEnabled
                .receive(on: RunLoop.main)
                .sink { [weak self] isEnabled in
                    guard let self else { return }
                    if isEnabled {
                        self.resetFileBackoff()
                        self.triggerFileResolution()
                    } else {
                        self.stopFilePolling()
                        self.fileBackoffLevel = 0
                        if var context = self.currentContext {
                            context.filePath = nil
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

            settings.$excludedFiles
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.enforceExclusionRules()
                }
                .store(in: &cancellables)

            settings.$assignmentRuleExpiration
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.startRuleExpirationMonitoring()
                }
                .store(in: &cancellables)
        }

        private func applyResolvedDomain(_ domain: String?, for application: NSRunningApplication) {
            guard isTrackingEnabled,
                  let domain,
                  var context = currentContext else { return }
            guard context.bundleIdentifier == application.bundleIdentifier else { return }
            let ignoreExclusions = isManualTrackingActive
            if ignoreExclusions, context.isExcluded {
                context.isExcluded = false
            }

            if !ignoreExclusions, settings.isDomainExcluded(domain) {
                logger.debug("Domain \(domain, privacy: .public) marked as excluded. Suspending tracking.")
                let source = context
                if let (_, endDate) = flushCurrentSession() {
                    let excludedContext = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: domain,
                        filePath: source.filePath,
                        startDate: endDate,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: true,
                        isPendingAssignment: false,
                    )
                    setCurrentContext(excludedContext)
                } else if var current = currentContext {
                    current.domain = domain
                    current.isExcluded = true
                    current.projectID = nil
                    current.projectName = nil
                    current.isPendingAssignment = false
                    current.startDate = .now
                    setCurrentContext(current)
                } else {
                    let excludedContext = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: domain,
                        filePath: source.filePath,
                        startDate: .now,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: true,
                        isPendingAssignment: false,
                    )
                    setCurrentContext(excludedContext)
                }
                return
            }

            if !ignoreExclusions, context.isExcluded {
                logger.debug("Domain \(domain, privacy: .public) is allowed again. Resuming tracking.")
                let source = context
                if let (_, endDate) = flushCurrentSession() {
                    var resumed = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: domain,
                        filePath: source.filePath,
                        startDate: endDate,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: false,
                        isPendingAssignment: false,
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
                        filePath: source.filePath,
                        startDate: .now,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: false,
                        isPendingAssignment: false,
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
                    filePath: previousContext.filePath,
                    startDate: endDate,
                    projectID: previousContext.projectID,
                    projectName: previousContext.projectName,
                    isExcluded: previousContext.isExcluded,
                    isPendingAssignment: previousContext.isPendingAssignment,
                ))
            } else if var current = currentContext {
                current.domain = domain
                if !current.isExcluded {
                    updateProjectAssociation(for: &current)
                }
                setCurrentContext(current)
            }
        }

        private func applyResolvedFilePath(_ filePath: String?, for application: NSRunningApplication) {
            guard isTrackingEnabled,
                  var context = currentContext else { return }
            guard context.bundleIdentifier == application.bundleIdentifier else { return }

            let normalized = filePath?.normalizedFilePath
            let sanitized = (normalized?.isEmpty == true) ? nil : normalized

            let ignoreExclusions = isManualTrackingActive
            if ignoreExclusions, context.isExcluded {
                context.isExcluded = false
            }

            if !ignoreExclusions, settings.isFileExcluded(sanitized) {
                logger.debug("File \(sanitized ?? "unknown", privacy: .public) marked as excluded. Suspending tracking.")
                let source = context
                if let (_, endDate) = flushCurrentSession() {
                    let excludedContext = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: source.domain,
                        filePath: sanitized,
                        startDate: endDate,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: true,
                        isPendingAssignment: false,
                    )
                    setCurrentContext(excludedContext)
                } else if var current = currentContext {
                    current.filePath = sanitized
                    current.isExcluded = true
                    current.projectID = nil
                    current.projectName = nil
                    current.isPendingAssignment = false
                    current.startDate = .now
                    setCurrentContext(current)
                } else {
                    let excludedContext = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: source.domain,
                        filePath: sanitized,
                        startDate: .now,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: true,
                        isPendingAssignment: false,
                    )
                    setCurrentContext(excludedContext)
                }
                return
            }

            if !ignoreExclusions, context.isExcluded {
                logger.debug("File \(sanitized ?? "unknown", privacy: .public) is allowed again. Resuming tracking.")
                let source = context
                if let (_, endDate) = flushCurrentSession() {
                    var resumed = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: source.domain,
                        filePath: sanitized,
                        startDate: endDate,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: false,
                        isPendingAssignment: false,
                    )
                    updateProjectAssociation(for: &resumed)
                    setCurrentContext(resumed)
                } else if var current = currentContext {
                    current.filePath = sanitized
                    current.isExcluded = false
                    current.startDate = .now
                    updateProjectAssociation(for: &current)
                    setCurrentContext(current)
                } else {
                    var resumed = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: source.domain,
                        filePath: sanitized,
                        startDate: .now,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: false,
                        isPendingAssignment: false,
                    )
                    updateProjectAssociation(for: &resumed)
                    setCurrentContext(resumed)
                }
                return
            }

            if context.filePath == nil {
                guard let sanitized else { return }
                context.filePath = sanitized
                updateProjectAssociation(for: &context)
                setCurrentContext(context)
                logger.debug("Detected file for \(context.appName, privacy: .public): \(sanitized, privacy: .public)")
                return
            }

            guard context.filePath != sanitized else { return }

            logger.debug("Detected file change for \(context.appName, privacy: .public)")
            if let (previousContext, endDate) = flushCurrentSession() {
                setCurrentContext(AppSessionContext(
                    appName: previousContext.appName,
                    bundleIdentifier: previousContext.bundleIdentifier,
                    domain: previousContext.domain,
                    filePath: sanitized,
                    startDate: endDate,
                    projectID: previousContext.projectID,
                    projectName: previousContext.projectName,
                    isExcluded: previousContext.isExcluded,
                    isPendingAssignment: previousContext.isPendingAssignment,
                ))
            } else if var current = currentContext {
                current.filePath = sanitized
                if !current.isExcluded {
                    updateProjectAssociation(for: &current)
                }
                setCurrentContext(current)
            }
        }

        private func enforceExclusionRules() {
            guard !isManualTrackingActive else { return }
            guard let context = currentContext else { return }
            let shouldExclude = settings.isAppExcluded(context.bundleIdentifier)
                || settings.isDomainExcluded(context.domain)
                || settings.isFileExcluded(context.filePath)
            if shouldExclude, !context.isExcluded {
                logger.debug("Current context became excluded after settings update")
                let source = context
                if let (_, endDate) = flushCurrentSession() {
                    let excludedContext = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: source.domain,
                        filePath: source.filePath,
                        startDate: endDate,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: true,
                        isPendingAssignment: false,
                    )
                    setCurrentContext(excludedContext)
                } else if var current = currentContext {
                    current.isExcluded = true
                    current.projectID = nil
                    current.projectName = nil
                    current.isPendingAssignment = false
                    current.startDate = .now
                    setCurrentContext(current)
                }
                return
            }

            if !shouldExclude, context.isExcluded {
                logger.debug("Context is no longer excluded; resuming tracking")
                let source = context
                if let (_, endDate) = flushCurrentSession() {
                    var resumed = AppSessionContext(
                        appName: source.appName,
                        bundleIdentifier: source.bundleIdentifier,
                        domain: source.domain,
                        filePath: source.filePath,
                        startDate: endDate,
                        projectID: nil,
                        projectName: nil,
                        isExcluded: false,
                        isPendingAssignment: false,
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
            rulesCleanupTimer?.invalidate()
            diagnosticsReporter?.stop()
            diagnosticsReporter = nil
        }

        private func startIdleMonitoring() {
            idleTimer?.invalidate()
            evaluateIdleState()
            guard isTrackingEnabled, !RuntimeFlags.isDisabled(.disableIdleCheck) else {
                if isUserIdle {
                    isUserIdle = false
                    idleBeganAt = nil
                    refreshStatusSummary()
                }
                return
            }
            let interval = max(idleCheckInterval, minimumTimerInterval)
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    Diagnostics.record(.idleCheckTick) {
                        self.evaluateIdleState()
                    }
                }
            }
            timer.tolerance = interval * 0.1
            idleTimer = timer
        }

        private func startScreenLockMonitoring() {
            stopScreenLockMonitoring()
            let center = DistributedNotificationCenter.default()
            screenLockObserver = center.addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenLockChange(isLocked: true)
                }
            }
            screenUnlockObserver = center.addObserver(
                forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main,
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
                if isManualTrackingActive {
                    stopManualTracking(reason: .screenLocked, resumeAutomatically: false)
                } else {
                    _ = flushCurrentSession()
                    setCurrentContext(nil)
                }
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

            if hasReachedIdle, !isUserIdle {
                isUserIdle = true
                idleBeganAt = Date()
                logger.notice("User became idle after \(idleSeconds, privacy: .public)s (threshold \(threshold, privacy: .public)s)")
                if isManualTrackingActive {
                    stopManualTracking(reason: .idle, resumeAutomatically: false)
                } else {
                    _ = flushCurrentSession()
                    setCurrentContext(nil)
                }
                refreshStatusSummary()
                return
            }

            if !hasReachedIdle, isUserIdle {
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
                0,
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
            if isManualTrackingActive {
                statusSummary = StatusSummary(
                    state: .trackingManual,
                    appName: context.appName,
                    domain: context.domain,
                    filePath: context.filePath,
                    bundleIdentifier: context.bundleIdentifier,
                    projectName: context.projectName,
                    projectID: context.projectID,
                )
                return
            }
            if context.isExcluded {
                statusSummary = StatusSummary(
                    state: .pausedExcluded,
                    appName: context.appName,
                    domain: context.domain,
                    filePath: context.filePath,
                    bundleIdentifier: context.bundleIdentifier,
                    projectName: nil,
                    projectID: nil,
                )
                return
            }
            if context.isPendingAssignment {
                statusSummary = StatusSummary(
                    state: .pendingResolution,
                    appName: context.appName,
                    domain: context.domain,
                    filePath: context.filePath,
                    bundleIdentifier: context.bundleIdentifier,
                    projectName: nil,
                    projectID: nil,
                )
                return
            }
            statusSummary = StatusSummary(
                state: .tracking,
                appName: context.appName,
                domain: context.domain,
                filePath: context.filePath,
                bundleIdentifier: context.bundleIdentifier,
                projectName: context.projectName,
                projectID: context.projectID,
            )
        }

        private func setCurrentContext(_ context: AppSessionContext?) {
            currentContext = context
            if !RuntimeFlags.isDisabled(.disableCrashRecovery) {
                crashRecovery.persist(snapshot: context.map {
                    SessionSnapshot(
                        context: $0,
                        isManualTrackingActive: isManualTrackingActive,
                        manualProjectID: manualProjectID,
                        manualStartDate: manualStartDate,
                    )
                })
            }
            refreshStatusSummary()
        }

        private func updateProjectAssociation(for context: inout AppSessionContext) {
            if isManualTrackingActive {
                applyManualProjectAssociation(to: &context)
                return
            }
            switch assignmentResolver.resolveAssignment(
                for: context.bundleIdentifier,
                domain: context.domain,
                filePath: context.filePath,
            ) {
            case let .assigned(project, _):
                context.projectID = project.persistentModelID
                context.projectName = project.name
                context.isPendingAssignment = false
            case .conflict:
                context.projectID = nil
                context.projectName = nil
                context.isPendingAssignment = true
            case .none:
                context.projectID = nil
                context.projectName = nil
                context.isPendingAssignment = false
            }
        }

        private func applyManualProjectAssociation(to context: inout AppSessionContext) {
            guard let manualProject = resolveManualProject() else {
                context.projectID = nil
                context.projectName = nil
                context.isPendingAssignment = false
                return
            }
            context.projectID = manualProject.persistentModelID
            context.projectName = manualProject.name
            context.isPendingAssignment = false
        }

        private func resolveManualProject() -> Project? {
            fetchManualProject(for: manualProjectID)
        }

        private func fetchManualProject(for identifier: PersistentIdentifier?) -> Project? {
            guard let identifier else { return nil }
            let descriptor = FetchDescriptor<Project>()
            guard let projects = try? Diagnostics.record(.swiftDataFetch, work: {
                try modelContainer.mainContext.fetch(descriptor)
            }) else { return nil }
            return projects.first(where: { $0.persistentModelID == identifier })
        }

        private func refreshPendingConflictCount() {
            let pendingDescriptor = FetchDescriptor<PendingTrackingSession>()
            let projectsDescriptor = FetchDescriptor<Project>()
            let pendingSessions = (try? Diagnostics.record(.swiftDataFetch, work: {
                try modelContainer.mainContext.fetch(pendingDescriptor)
            })) ?? []
            guard !pendingSessions.isEmpty else {
                pendingConflictCount = 0
                return
            }
            let projects = (try? Diagnostics.record(.swiftDataFetch, work: {
                try modelContainer.mainContext.fetch(projectsDescriptor)
            })) ?? []
            guard !projects.isEmpty else {
                pendingSessions.forEach(modelContainer.mainContext.delete)
                pendingConflictCount = 0
                return
            }
            let grouped = Dictionary(grouping: pendingSessions) {
                "\($0.contextType)::\($0.contextValue)"
            }
            var removed = 0
            let count = grouped.values.reduce(into: 0) { partial, sessions in
                guard let first = sessions.first else { return }
                let type = AssignmentContextType(rawValue: first.contextType) ?? .app
                let hasCandidates = projects.contains { project in
                    switch type {
                    case .app:
                        return project.matches(appBundleIdentifier: first.contextValue)
                    case .domain:
                        return project.matches(domain: first.contextValue)
                    case .file:
                        return project.matches(filePath: first.contextValue)
                    }
                }
                if hasCandidates {
                    partial += 1
                } else {
                    sessions.forEach(modelContainer.mainContext.delete)
                    removed += sessions.count
                }
            }
            pendingConflictCount = count
            if removed > 0, !RuntimeFlags.isDisabled(.disableSwiftDataWrites) {
                try? Diagnostics.record(.swiftDataSave) {
                    try modelContainer.mainContext.save()
                }
            }
        }

        private func scheduleSwiftDataSave() {
            guard !RuntimeFlags.isDisabled(.disableSwiftDataWrites) else { return }
            pendingSwiftDataSave = true
            let now = Date()
            if pendingSwiftDataSaveSince == nil {
                pendingSwiftDataSaveSince = now
            }
            lastSwiftDataSaveRequestAt = now
            guard swiftDataSaveTask == nil else { return }
            swiftDataSaveTask = Task { @MainActor [weak self] in
                await self?.runSwiftDataSaveLoop()
            }
        }

        private func runSwiftDataSaveLoop() async {
            while !Task.isCancelled {
                guard pendingSwiftDataSave else {
                    pendingSwiftDataSaveSince = nil
                    lastSwiftDataSaveRequestAt = nil
                    swiftDataSaveTask = nil
                    return
                }

                let now = Date()
                let pendingSince = pendingSwiftDataSaveSince ?? now
                let lastRequestAt = lastSwiftDataSaveRequestAt ?? pendingSince
                let sinceFirst = now.timeIntervalSince(pendingSince)
                let sinceLast = now.timeIntervalSince(lastRequestAt)
                let shouldDelay = sinceLast < saveDebounceInterval && sinceFirst < saveMaxInterval

                if shouldDelay {
                    let delay = min(saveDebounceInterval - sinceLast, saveMaxInterval - sinceFirst)
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        pendingSwiftDataSaveSince = nil
                        lastSwiftDataSaveRequestAt = nil
                        swiftDataSaveTask = nil
                        return
                    }
                    continue
                }

                pendingSwiftDataSave = false
                pendingSwiftDataSaveSince = nil
                lastSwiftDataSaveRequestAt = nil
                do {
                    try Diagnostics.record(.swiftDataSave) {
                        try modelContainer.mainContext.save()
                    }
                } catch {
                    logger.error("Failed to save SwiftData: \(error.localizedDescription, privacy: .public)")
                }

                if !pendingSwiftDataSave {
                    swiftDataSaveTask = nil
                    return
                }
            }
            swiftDataSaveTask = nil
        }

        private func pauseTimers() {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            stopDomainPolling()
            stopFilePolling()
            idleTimer?.invalidate()
            idleTimer = nil
        }

        private func restartTimersIfNeeded() {
            guard isTrackingEnabled else { return }
            startHeartbeat()
            startIdleMonitoring()
            updateResolutionPolling(for: currentContext)
        }

        private func domainPollingInterval() -> TimeInterval {
            let base = max(TrackerSettings.minDetectionInterval, settings.detectionInterval)
            let interval = base * pow(2, Double(domainBackoffLevel))
            return max(minimumTimerInterval, min(interval, maxResolutionInterval))
        }

        private func filePollingInterval() -> TimeInterval {
            let base = max(TrackerSettings.minDetectionInterval, settings.detectionInterval)
            let interval = base * pow(2, Double(fileBackoffLevel))
            return max(minimumTimerInterval, min(interval, maxResolutionInterval))
        }

        private func resetDomainBackoff() {
            guard domainBackoffLevel != 0 else {
                updateResolutionPolling(for: currentContext)
                return
            }
            domainBackoffLevel = 0
            updateResolutionPolling(for: currentContext)
        }

        private func resetFileBackoff() {
            guard fileBackoffLevel != 0 else {
                updateResolutionPolling(for: currentContext)
                return
            }
            fileBackoffLevel = 0
            updateResolutionPolling(for: currentContext)
        }

        private func bumpDomainBackoffIfNeeded() {
            let previous = domainBackoffLevel
            domainBackoffLevel = min(domainBackoffLevel + 1, 4)
            if previous != domainBackoffLevel {
                updateResolutionPolling(for: currentContext)
            }
        }

        private func bumpFileBackoffIfNeeded() {
            let previous = fileBackoffLevel
            fileBackoffLevel = min(fileBackoffLevel + 1, 4)
            if previous != fileBackoffLevel {
                updateResolutionPolling(for: currentContext)
            }
        }

        private func updateResolutionPolling(for context: AppSessionContext?) {
            guard isTrackingEnabled else {
                stopDomainPolling()
                stopFilePolling()
                return
            }

            if let context,
               settings.isDomainTrackingEnabled,
               !context.isExcluded,
               domainResolver.supports(bundleIdentifier: context.bundleIdentifier)
            {
                startDomainPolling()
            } else {
                stopDomainPolling()
            }

            if let context,
               settings.isFileTrackingEnabled,
               !context.isExcluded,
               fileResolver.supports(bundleIdentifier: context.bundleIdentifier)
            {
                startFilePolling()
            } else {
                stopFilePolling()
            }
        }

        private func stopDomainPolling() {
            domainTimer?.invalidate()
            domainTimer = nil
        }

        private func stopFilePolling() {
            fileTimer?.invalidate()
            fileTimer = nil
        }

        private func startRuleExpirationMonitoring() {
            rulesCleanupTimer?.invalidate()
            rulesCleanupTimer = nil
            guard settings.assignmentRuleExpiration.days != nil else { return }
            let interval = max(rulesCleanupInterval, minimumTimerInterval)
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.purgeExpiredRules()
                }
            }
            timer.tolerance = interval * 0.1
            rulesCleanupTimer = timer
            purgeExpiredRules()
        }

        private func purgeExpiredRules() {
            guard let cutoff = settings.assignmentRuleExpiration.cutoffDate() else { return }
            let descriptor = FetchDescriptor<AssignmentRule>()
            guard let rules = try? Diagnostics.record(.swiftDataFetch, work: {
                try modelContainer.mainContext.fetch(descriptor)
            }) else { return }
            let expired = rules.filter { isRuleExpired($0, cutoff: cutoff) }
            guard !expired.isEmpty else { return }
            expired.forEach { modelContainer.mainContext.delete($0) }
            do {
                try Diagnostics.record(.swiftDataSave) {
                    try modelContainer.mainContext.save()
                }
                logger.info("Purged \(expired.count, privacy: .public) expired assignment rules")
            } catch {
                logger.error("Failed to purge expired assignment rules: \(error.localizedDescription, privacy: .public)")
            }
        }

        private func isRuleExpired(_ rule: AssignmentRule, cutoff: Date) -> Bool {
            rule.effectiveLastUsedAt < cutoff
        }

        @MainActor
        func resolveConflict(context: AssignmentContext, project: Project) {
            let typeValue = context.type.rawValue
            let contextValue = context.value
            let ruleDescriptor = FetchDescriptor<AssignmentRule>(
                predicate: #Predicate {
                    $0.contextType == typeValue &&
                        $0.contextValue == contextValue
                },
            )
            if let rule = try? Diagnostics.record(.swiftDataFetch, work: {
                try modelContainer.mainContext.fetch(ruleDescriptor).first
            }) {
                rule.project = project
                rule.lastUsedAt = .now
            } else {
                let rule = AssignmentRule(
                    contextType: context.type.rawValue,
                    contextValue: context.value,
                    project: project,
                )
                modelContainer.mainContext.insert(rule)
            }

            let pendingDescriptor = FetchDescriptor<PendingTrackingSession>(
                predicate: #Predicate {
                    $0.contextType == typeValue &&
                        $0.contextValue == contextValue
                },
            )
            guard let pendingSessions = try? Diagnostics.record(.swiftDataFetch, work: {
                try modelContainer.mainContext.fetch(pendingDescriptor)
            }),
                !pendingSessions.isEmpty
            else {
                refreshPendingConflictCount()
                return
            }

            var resolvedCount = 0
            for pending in pendingSessions {
                guard pending.endDate > pending.startDate else {
                    modelContainer.mainContext.delete(pending)
                    continue
                }
                let sessionContext = AppSessionContext(
                    appName: pending.appName,
                    bundleIdentifier: pending.bundleIdentifier,
                    domain: pending.domain,
                    filePath: pending.filePath,
                    startDate: pending.startDate,
                    projectID: nil,
                    projectName: project.name,
                    isExcluded: false,
                    isPendingAssignment: false,
                )
                insertResolvedSession(context: sessionContext, endDate: pending.endDate, project: project)
                modelContainer.mainContext.delete(pending)
                resolvedCount += 1
            }

            do {
                try Diagnostics.record(.swiftDataSave) {
                    try modelContainer.mainContext.save()
                }
                refreshPendingConflictCount()
                logger.info("Resolved \(resolvedCount, privacy: .public) pending sessions for \(context.value, privacy: .public)")
            } catch {
                logger.error("Failed to resolve pending sessions: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private struct AppSessionContext {
        var appName: String
        var bundleIdentifier: String?
        var domain: String?
        var filePath: String?
        var startDate: Date
        var projectID: PersistentIdentifier?
        var projectName: String?
        var isExcluded: Bool
        var isPendingAssignment: Bool
    }

    private extension SessionSnapshot {
        init(
            context: AppSessionContext,
            isManualTrackingActive: Bool,
            manualProjectID: PersistentIdentifier?,
            manualStartDate: Date?,
        ) {
            self.init(
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                domain: context.domain,
                filePath: context.filePath,
                startDate: context.startDate,
                projectName: context.projectName,
                isExcluded: context.isExcluded,
                isManualTrackingActive: isManualTrackingActive,
                manualProjectID: manualProjectID,
                manualStartDate: manualStartDate,
            )
        }
    }

    #if DEBUG
        extension ActivityTracker {
            func testing_startManualTracking(project: Project) {
                isTrackingEnabled = true
                isManualTrackingActive = true
                manualProjectID = project.persistentModelID
                manualStartDate = Date()
                refreshStatusSummary()
            }

            func testing_beginContext(
                appName: String,
                bundleIdentifier: String? = nil,
                domain: String? = nil,
                filePath: String? = nil,
                startDate: Date = Date().addingTimeInterval(-20),
                isExcluded: Bool = false,
            ) {
                _ = flushCurrentSession()
                var context = AppSessionContext(
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    domain: domain,
                    filePath: filePath,
                    startDate: startDate,
                    projectID: nil,
                    projectName: nil,
                    isExcluded: isExcluded,
                    isPendingAssignment: false,
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

            func testing_disableIdleMonitoring() {
                idleTimer?.invalidate()
                idleTimer = nil
                isUserIdle = false
                idleBeganAt = nil
                refreshStatusSummary()
            }

            @discardableResult
            func testing_forceFlush() -> Bool {
                flushCurrentSession() != nil
            }
        }
    #endif

    @MainActor
    private final class BrowserDomainResolver {
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "BrowserDomainResolver")

        func supports(bundleIdentifier: String?) -> Bool {
            guard let bundleIdentifier else { return false }
            return BrowserFamily(bundleIdentifier: bundleIdentifier) != nil
        }

        func resolveDomain(for application: NSRunningApplication) async -> String? {
            guard let identifier = application.bundleIdentifier,
                  let browser = BrowserFamily(bundleIdentifier: identifier)
            else {
                return nil
            }

            let script: String = switch browser {
            case let .safari(bundleIdentifier):
                BrowserFamily.safariScript(bundleIdentifier: bundleIdentifier)
            case let .chrome(bundleIdentifier):
                BrowserFamily.chromeScript(bundleIdentifier: bundleIdentifier)
            }

            return await BrowserScriptRunner.run(script: script, identifier: browser.identifier, logger: logger)
        }

        private enum BrowserFamily {
            case safari(bundleIdentifier: String)
            case chrome(bundleIdentifier: String)

            var identifier: String {
                switch self {
                case let .safari(bundleIdentifier), let .chrome(bundleIdentifier):
                    bundleIdentifier
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

            fileprivate static func safariScript(bundleIdentifier: String) -> String {
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

            fileprivate static func chromeScript(bundleIdentifier: String) -> String {
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

            fileprivate nonisolated static func domain(from urlString: String) -> String? {
                let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                var normalized = trimmed
                if !normalized.contains("://") {
                    normalized = "https://\(normalized)"
                }
                guard let url = URL(string: normalized),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      var host = url.host?.lowercased()
                else {
                    return nil
                }
                if host.hasPrefix("www.") {
                    host.removeFirst(4)
                }
                return host
            }
        }

        private nonisolated enum BrowserScriptRunner {
            @concurrent
            static func run(script: String, identifier: String, logger: Logger) async -> String? {
                guard let urlString = await AppleScriptRunner.run(script: script, identifier: identifier, logger: logger) else {
                    return nil
                }
                guard let domain = BrowserFamily.domain(from: urlString)
                else {
                    return nil
                }
                logger.debug("Resolved browser domain: \(domain, privacy: .public)")
                return domain
            }
        }
    }
#else
    /// Placeholder implementation so previews build on other platforms.
    final class ActivityTracker: ObservableObject {
        init(modelContainer _: ModelContainer) {}
        func toggleTracking() {}
    }
#endif
