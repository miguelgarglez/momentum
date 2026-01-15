//
//  DebugOverlayView.swift
//  Momentum
//
//  Created by Codex on 14/01/26.
//

import Combine
import SwiftUI

struct DebugOverlayView: View {
    @ObservedObject var tracker: ActivityTracker
    let performanceMonitor: PerformanceBudgetMonitor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            trackingSection
            if let performanceMonitor {
                Divider()
                DebugOverlayPerformanceView(performanceMonitor: performanceMonitor)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .onReceive(tracker.objectWillChange) { _ in
            Diagnostics.record(.overlayRefresh) {}
        }
        .modifier(OverlayPerformanceObserver(performanceMonitor: performanceMonitor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Debug")
                .font(.caption)
                .fontWeight(.semibold)
            Text("Overlay")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(Date(), format: .dateTime.hour().minute().second())
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            DebugOverlayRow(label: "Estado", value: stateLabel)
            DebugOverlayRow(label: "Tracking", value: tracker.isTrackingEnabled ? "on" : "off")
            DebugOverlayRow(label: "Manual", value: tracker.isManualTrackingActive ? "on" : "off")
            DebugOverlayRow(label: "Pendientes", value: "\(tracker.pendingConflictCount)")
            DebugOverlayRow(label: "App", value: tracker.statusSummary.appName ?? "—")
            DebugOverlayRow(label: "Proyecto", value: tracker.statusSummary.projectName ?? "—")
            DebugOverlayRow(label: "Dominio", value: tracker.statusSummary.domain ?? "—")
            DebugOverlayRow(label: "Archivo", value: tracker.statusSummary.filePath ?? "—")
        }
    }

    private var stateLabel: String {
        switch tracker.statusSummary.state {
        case .inactive:
            return "inactivo"
        case .tracking:
            return "tracking"
        case .trackingManual:
            return "manual"
        case .pendingResolution:
            return "pendiente"
        case .pausedManual:
            return "pausa manual"
        case .pausedIdle:
            return "pausa idle"
        case .pausedScreenLocked:
            return "pausa lock"
        case .pausedExcluded:
            return "excluido"
        }
    }
}

private struct OverlayPerformanceObserver: ViewModifier {
    let performanceMonitor: PerformanceBudgetMonitor?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let performanceMonitor {
            content.onReceive(performanceMonitor.objectWillChange) { _ in
                Diagnostics.record(.overlayRefresh) {}
            }
        } else {
            content
        }
    }
}

struct DebugOverlayPerformanceView: View {
    @ObservedObject var performanceMonitor: PerformanceBudgetMonitor

    private var recentSamples: ArraySlice<PerformanceBudgetMonitor.MetricSample> {
        performanceMonitor.recentSamples.suffix(6)
    }

    private var recentPollSamples: [PerformanceBudgetMonitor.MetricSample] {
        recentSamples.filter { sample in
            if case .poll = sample.source {
                return true
            }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DebugOverlayRow(label: "CPU avg", value: cpuAverageText)
            DebugOverlayRow(label: "CPU last", value: cpuLatestText)
            DebugOverlayRow(label: "CPU poll", value: cpuPollAverageText)
            DebugOverlayRow(label: "IO avg", value: ioAverageText)
            DebugOverlayRow(label: "Samples", value: "\(performanceMonitor.recentSamples.count)")
            DebugOverlayRow(label: "Violaciones", value: "\(performanceMonitor.violations.count)")
        }
    }

    private var cpuAverageText: String {
        let values = recentSamples.map { $0.cpuLoad }
        guard !values.isEmpty else { return "—" }
        let avg = values.reduce(0, +) / Double(values.count)
        return percentText(avg)
    }

    private var cpuPollAverageText: String {
        let values = recentPollSamples.map { $0.cpuLoad }
        guard !values.isEmpty else { return "—" }
        let avg = values.reduce(0, +) / Double(values.count)
        return percentText(avg)
    }

    private var cpuLatestText: String {
        guard let latest = performanceMonitor.recentSamples.last else { return "—" }
        return percentText(latest.cpuLoad)
    }

    private var ioAverageText: String {
        let values = recentSamples.map { $0.ioBytesPerSecond }
        guard !values.isEmpty else { return "—" }
        let avg = values.reduce(0, +) / Double(values.count)
        return ioText(avg)
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func ioText(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1f MB/s", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0f KB/s", value / 1_000)
        }
        return String(format: "%.0f B/s", value)
    }
}

struct DebugOverlayRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

struct DebugOverlayModifier: ViewModifier {
    let isEnabled: Bool
    let tracker: ActivityTracker
    let performanceMonitor: PerformanceBudgetMonitor?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isEnabled && !RuntimeFlags.isDisabled(.disableOverlayUpdates) {
                    DebugOverlayView(tracker: tracker, performanceMonitor: performanceMonitor)
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func debugOverlay(
        isEnabled: Bool,
        tracker: ActivityTracker,
        performanceMonitor: PerformanceBudgetMonitor?
    ) -> some View {
        modifier(DebugOverlayModifier(
            isEnabled: isEnabled,
            tracker: tracker,
            performanceMonitor: performanceMonitor
        ))
    }
}
