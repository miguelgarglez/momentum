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
    let onToggleTracking: () -> Void
    let onCreateProject: () -> Void
    let settingsControl: AnyView

    private var toggleLabel: String {
        isTrackingEnabled ? "Pausar tracking" : "Reanudar tracking"
    }

    private var toggleIcon: String {
        isTrackingEnabled ? "pause.circle.fill" : "play.circle.fill"
    }

    private var trackingBadgeColor: Color {
        switch summary.state {
        case .tracking:
            return .accentColor
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
                    systemName: toggleIcon,
                    tint: trackingBadgeColor,
                    accessibilityLabel: toggleLabel,
                    action: onToggleTracking
                )

                ActionPanelIconButton(
                    systemName: "plus",
                    tint: .primary,
                    accessibilityLabel: "Nuevo proyecto",
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
    let action: () -> Void
    var isActive: Bool = false

    var body: some View {
        Button(action: action) {
            ActionPanelIcon(systemName: systemName, tint: tint, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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
