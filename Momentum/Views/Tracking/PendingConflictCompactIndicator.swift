//
//  PendingConflictCompactIndicator.swift
//  Momentum
//
//  Created by Miguel García González on 19/01/26.
//

import SwiftUI

struct PendingConflictCompactIndicator: View {
    let count: Int
    let action: () -> Void

    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    private var badgeText: String {
        count > 99 ? "99+" : "\(count)"
    }

    private var accessibilitySummary: String {
        let label = count == 1 ? String(localized: "conflicto pendiente") : String(localized: "conflictos pendientes")
        return String.localizedStringWithFormat(String(localized: "Resolver %@ %@"), String(count), label)
    }

    private var tooltipText: String {
        let label = count == 1 ? String(localized: "conflicto pendiente") : String(localized: "conflictos pendientes")
        return String.localizedStringWithFormat(String(localized: "%@ %@ por resolver"), String(count), label)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ActionPanelIcon(systemName: "exclamationmark.triangle.fill", tint: .orange)

                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.orange),
                    )
                    .offset(x: 8, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("pending-conflict-compact-button")
        .overlay(alignment: .topLeading) {
            if showTooltip {
                ChartTooltipView(text: tooltipText)
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
