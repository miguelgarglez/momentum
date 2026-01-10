//
//  ActionPanelView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI

struct ActionPanelView: View {
    let summary: ActivityTracker.StatusSummary
    let isTrackingEnabled: Bool
    let isManualTrackingActive: Bool
    let onToggleTracking: () -> Void
    let onStartManualTracking: () -> Void
    let onCreateProject: () -> Void
    let settingsControl: AnyView

    private var primaryActionLabel: String {
        if isManualTrackingActive {
            return "Detener manual"
        }
        return isTrackingEnabled ? "Pausar tracking" : "Reanudar tracking"
    }

    private var primaryActionIcon: String {
        if isManualTrackingActive {
            return "stop.circle.fill"
        }
        return isTrackingEnabled ? "pause.circle.fill" : "play.circle.fill"
    }

    private var manualLabel: String {
        isManualTrackingActive ? "Tracking manual activo" : "Iniciar tracking manual"
    }

    private var manualTint: Color {
        isManualTrackingActive ? .cyan : .primary
    }

    private var trackingBadgeColor: Color {
        switch summary.state {
        case .tracking:
            return .accentColor
        case .trackingManual:
            return .cyan
        case .pendingResolution:
            return .orange
        case .pausedManual:
            return .orange
        case .pausedIdle:
            return .yellow
        case .pausedScreenLocked:
            return .blue
        case .pausedExcluded:
            return .secondary
        case .inactive:
            return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: 10) {
                ActionPanelIconButton(
                    systemName: primaryActionIcon,
                    tint: trackingBadgeColor,
                    accessibilityLabel: primaryActionLabel,
                    accessibilityIdentifier: "action-panel-primary",
                    action: onToggleTracking
                )

                ActionPanelIconButton(
                    systemName: "record.circle",
                    tint: manualTint,
                    accessibilityLabel: manualLabel,
                    accessibilityIdentifier: "action-panel-manual",
                    action: onStartManualTracking,
                    isActive: isManualTrackingActive
                )
                .disabled(isManualTrackingActive)

                ActionPanelIconButton(
                    systemName: "plus",
                    tint: .primary,
                    accessibilityLabel: "Nuevo proyecto",
                    accessibilityIdentifier: "action-panel-create-project",
                    action: onCreateProject
                )

                settingsControl
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ActionPanelIconButton: View {
    let systemName: String
    let tint: Color
    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let action: () -> Void
    var isActive: Bool = false

    var body: some View {
        let button = Button(action: action) {
            ActionPanelIcon(systemName: systemName, tint: tint, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)

        if let accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}

struct ActionPanelIcon: View {
    let systemName: String
    let tint: Color
    var isActive: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : tint)
            .frame(width: 36, height: 36)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
