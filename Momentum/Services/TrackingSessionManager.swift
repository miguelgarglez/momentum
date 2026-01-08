//
//  TrackingSessionManager.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation

@MainActor
final class TrackingSessionManager: ObservableObject {
    @Published private(set) var isTrackingActive: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recentApps: [String] = []
    @Published private(set) var recentDomains: [String] = []

    private var startDate: Date?
    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    func updateTrackingState(isActive: Bool) {
        guard isActive != isTrackingActive else { return }
        isTrackingActive = isActive
        if isActive {
            startDate = Date()
            startTimer()
        } else {
            stopTimer()
            recentApps.removeAll()
            recentDomains.removeAll()
            elapsed = 0
            startDate = nil
        }
    }

    func ingest(summary: ActivityTracker.StatusSummary) {
        guard isTrackingActive else { return }
        if let appName = summary.appName, !appName.isEmpty {
            insertUnique(appName, into: &recentApps)
        }
        if let domain = summary.domain, !domain.isEmpty {
            insertUnique(domain, into: &recentDomains)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        updateElapsed()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsed() {
        guard let startDate else { return }
        elapsed = Date().timeIntervalSince(startDate)
    }

    private func insertUnique(_ value: String, into list: inout [String], limit: Int = 6) {
        if let index = list.firstIndex(of: value) {
            list.remove(at: index)
        }
        list.insert(value, at: 0)
        if list.count > limit {
            list = Array(list.prefix(limit))
        }
    }
}
