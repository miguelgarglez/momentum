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
    private var currentContext: AppSessionContext?
    private var observer: NSObjectProtocol?
    private var timer: Timer?

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
            flushCurrentSession()
        }
    }

    private func handleAppChange(_ application: NSRunningApplication?) {
        flushCurrentSession()
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
            startDate: .now
        )
    }

    private func flushCurrentSession() {
        guard var context = currentContext else { return }
        let endDate = Date()
        if endDate.timeIntervalSince(context.startDate) < 10 {
            context.startDate = endDate
            currentContext = context
            return
        }
        let identifier = context.bundleIdentifier ?? context.appName
        logger.debug("Closing session for \(identifier, privacy: .public)")
        persistSession(context: context, endDate: endDate)
        currentContext = AppSessionContext(
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            startDate: endDate
        )
    }

    private func persistSession(context: AppSessionContext, endDate: Date) {
        let session = TrackingSession(
            startDate: context.startDate,
            endDate: endDate,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            domain: nil,
            project: resolveProject(for: context.bundleIdentifier, domain: nil)
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
        guard let bundleIdentifier = bundleIdentifier else { return nil }
        let descriptor = FetchDescriptor<Project>()
        guard let projects = try? modelContainer.mainContext.fetch(descriptor) else {
            return nil
        }

        if let match = projects.first(where: { $0.matches(appBundleIdentifier: bundleIdentifier) }) {
            return match
        }

        if let domain,
           let match = projects.first(where: { $0.matches(domain: domain) }) {
            return match
        }

        return nil
    }

    private func startHeartbeat() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.logger.debug("Heartbeat flush triggered")
            self.flushCurrentSession()
        }
    }

    private func tearDown() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        timer?.invalidate()
        timer = nil
    }
}

private struct AppSessionContext {
    var appName: String
    var bundleIdentifier: String?
    var startDate: Date
}
#else
/// Placeholder implementation so previews build on other platforms.
final class ActivityTracker: ObservableObject {
    init(modelContainer: ModelContainer) {}
    func toggleTracking() {}
}
#endif
