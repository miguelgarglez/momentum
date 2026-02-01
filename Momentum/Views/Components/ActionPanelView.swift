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
    let statusAccessory: AnyView?

    private enum Layout {
        static let statusAccessoryOffset: CGFloat = 0
        static let leadingInset: CGFloat = 22
        static let trailingInset: CGFloat = 12
    }

    static let minimumHeight: CGFloat = {
        let iconSize: CGFloat = 36
        let iconPadding: CGFloat = 6
        let buttonSize = iconSize + iconPadding * 2
        let buttonCount: CGFloat = 4
        let buttonSpacing: CGFloat = 10
        let verticalPadding: CGFloat = 40
        return buttonCount * buttonSize + (buttonCount - 1) * buttonSpacing + verticalPadding
    }()

    init(
        summary: ActivityTracker.StatusSummary,
        isTrackingEnabled: Bool,
        isManualTrackingActive: Bool,
        onToggleTracking: @escaping () -> Void,
        onStartManualTracking: @escaping () -> Void,
        onCreateProject: @escaping () -> Void,
        settingsControl: AnyView,
        statusAccessory: AnyView? = nil
    ) {
        self.summary = summary
        self.isTrackingEnabled = isTrackingEnabled
        self.isManualTrackingActive = isManualTrackingActive
        self.onToggleTracking = onToggleTracking
        self.onStartManualTracking = onStartManualTracking
        self.onCreateProject = onCreateProject
        self.settingsControl = settingsControl
        self.statusAccessory = statusAccessory
    }

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
            .accentColor
        case .trackingManual:
            .cyan
        case .pendingResolution:
            .orange
        case .pausedManual:
            .orange
        case .pausedIdle:
            .yellow
        case .pausedScreenLocked:
            .blue
        case .pausedExcluded:
            .secondary
        case .inactive:
            .secondary
        }
    }

    private var statusAccessoryTopPadding: CGFloat {
        Layout.statusAccessoryOffset
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let statusAccessory {
                statusAccessory
                    .offset(y: statusAccessoryTopPadding)
                    .animation(.none, value: statusAccessoryTopPadding)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }

            VStack(alignment: .center, spacing: 16) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 10) {
                    ActionPanelIconButton(
                        systemName: primaryActionIcon,
                        tint: trackingBadgeColor,
                        accessibilityLabel: primaryActionLabel,
                        accessibilityIdentifier: "action-panel-primary",
                        tooltipText: primaryActionLabel,
                        action: onToggleTracking,
                    )

                    ActionPanelIconButton(
                        systemName: "record.circle",
                        tint: manualTint,
                        accessibilityLabel: manualLabel,
                        accessibilityIdentifier: "action-panel-manual",
                        tooltipText: manualLabel,
                        action: onStartManualTracking,
                        isActive: isManualTrackingActive,
                    )
                    .disabled(isManualTrackingActive)

                    ActionPanelIconButton(
                        systemName: "plus",
                        tint: .primary,
                        accessibilityLabel: "Nuevo proyecto",
                        accessibilityIdentifier: "action-panel-create-project",
                        tooltipText: "Nuevo proyecto",
                        action: onCreateProject,
                    )

                    settingsControl
                        .actionPanelTooltip("Ajustes")
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.leading, Layout.leadingInset)
        .padding(.trailing, Layout.trailingInset)
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ActionPanelIconButton: View {
    let systemName: String
    let tint: Color
    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let tooltipText: String?
    let action: () -> Void
    var isActive: Bool = false

    var body: some View {
        let button = Button(action: action) {
            ActionPanelIcon(systemName: systemName, tint: tint, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .actionPanelTooltip(tooltipText)

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
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08)),
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    @ViewBuilder
    func actionPanelTooltip(_ text: String?) -> some View {
        #if os(macOS)
            if let text {
                modifier(ActionPanelHoverTooltip(text: text))
            } else {
                self
            }
        #else
            self
        #endif
    }
}

#if os(macOS)
private struct ActionPanelHoverTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if showTooltip {
                    ChartTooltipView(text: text)
                        .offset(x: 0, y: -28)
                        .transition(
                            .opacity
                                .combined(with: .move(edge: .top))
                                .combined(with: .scale(scale: 0.96, anchor: .bottomLeading)),
                        )
                        .zIndex(1)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    hoverTask?.cancel()
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled, isHovering else { return }
                        showTooltip = true
                    }
                } else {
                    hoverTask?.cancel()
                    showTooltip = false
                }
            }
            .onDisappear {
                hoverTask?.cancel()
            }
            .animation(.easeInOut(duration: 0.12), value: showTooltip)
    }
}
#endif
