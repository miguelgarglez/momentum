import Foundation
import OSLog
import SwiftData
#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

struct SessionSnapshot: Codable, Equatable {
    var appName: String
    var bundleIdentifier: String?
    var domain: String?
    var filePath: String?
    var startDate: Date
    var projectName: String?
    var isExcluded: Bool
    var isManualTrackingActive: Bool?
    var manualProjectID: PersistentIdentifier?
    var manualStartDate: Date?
}

/// Abstraction for components that can persist and restore crash recovery
/// metadata for the tracker.
///
/// Implementations are responsible for storing enough information to resume
/// pending sessions, and for exposing a lightweight API that `ActivityTracker`
/// can call during startup and at flush boundaries.
@MainActor
protocol CrashRecoveryHandling: AnyObject {
    func persist(snapshot: SessionSnapshot?)
    func consumePendingSnapshot() -> SessionSnapshot?
}

/// Persists and restores in‑flight tracking state so Momentum can recover
/// gracefully after a crash or forced termination.
///
/// `CrashRecoveryManager` snapshots pending session contexts and any other
/// transient tracker state to disk, and exposes APIs for replaying or discarding
/// that state on the next app launch. This allows `ActivityTracker` to resume
/// from a consistent point without silently dropping user activity.
@MainActor
final class CrashRecoveryManager: ObservableObject, CrashRecoveryHandling {
    private enum Keys {
        static let snapshot = "momentum.crash.snapshot"
        static let cleanShutdown = "momentum.crash.cleanShutdown"
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "CrashRecovery")
    private var hadUncleanShutdown: Bool
    private var lastSnapshot: SessionSnapshot?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let wasClean = defaults.bool(forKey: Keys.cleanShutdown)
        hadUncleanShutdown = !wasClean
        defaults.set(false, forKey: Keys.cleanShutdown)
        registerTerminationObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func persist(snapshot: SessionSnapshot?) {
        if snapshot == lastSnapshot {
            return
        }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Keys.snapshot)
            lastSnapshot = snapshot
        } else {
            defaults.removeObject(forKey: Keys.snapshot)
            lastSnapshot = nil
        }
    }

    func consumePendingSnapshot() -> SessionSnapshot? {
        guard hadUncleanShutdown,
              let data = defaults.data(forKey: Keys.snapshot),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data)
        else {
            return nil
        }
        defaults.removeObject(forKey: Keys.snapshot)
        logger.notice("Crash recovery restoring session for \(snapshot.appName, privacy: .public)")
        return snapshot
    }

    @objc private func markTerminationClean() {
        defaults.set(true, forKey: Keys.cleanShutdown)
        defaults.synchronize()
    }

    private func registerTerminationObserver() {
        #if os(macOS)
            NotificationCenter.default.addObserver(self, selector: #selector(markTerminationClean), name: NSApplication.willTerminateNotification, object: nil)
        #elseif os(iOS)
            NotificationCenter.default.addObserver(self, selector: #selector(markTerminationClean), name: UIApplication.willTerminateNotification, object: nil)
        #endif
    }
}

@MainActor
final class NoopCrashRecoveryManager: CrashRecoveryHandling {
    func persist(snapshot _: SessionSnapshot?) {
        // no-op for tests
    }

    func consumePendingSnapshot() -> SessionSnapshot? {
        nil
    }
}
