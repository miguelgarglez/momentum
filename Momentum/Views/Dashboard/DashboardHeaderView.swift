import SwiftUI

struct DashboardMetricsDisplay {
    let total: String
    let monthly: String
    let weekly: String
    let daily: String

    static let loading = DashboardMetricsDisplay(
        total: "…",
        monthly: "…",
        weekly: "…",
        daily: "…",
    )
}

struct DashboardHeaderView: View {
    let metrics: DashboardMetricsDisplay
    @AppStorage("dashboardSummaryExpanded") private var isExpanded = true

    fileprivate enum Layout {
        static let headerSpacing: CGFloat = 6
        static let cardPadding: CGFloat = 10
        static let cornerRadius: CGFloat = 18
        static let strokeOpacity: Double = 0.08
        static let metricSpacing: CGFloat = 8
        static let metricMinHeight: CGFloat = 54
        static let compactMetricMinHeight: CGFloat = 46
        static let metricColumns: [GridItem] = [
            GridItem(.flexible(), spacing: metricSpacing),
            GridItem(.flexible(), spacing: metricSpacing),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.metricSpacing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text("Mide tu progreso, no tu productividad.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dashboard-welcome-text")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 14, height: 14, alignment: .center)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Ocultar resumen" : "Mostrar resumen")

            if isExpanded {
                DashboardMetricsView(
                    total: metrics.total,
                    monthly: metrics.monthly,
                    weekly: metrics.weekly,
                    daily: metrics.daily,
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cornerRadius,
            strokeOpacity: Layout.strokeOpacity,
        )
        .accessibilityElement(children: .contain)
    }
}

struct DashboardMetricsView: View {
    let total: String
    let monthly: String
    let weekly: String
    let daily: String

    private struct MetricInfo: Identifiable {
        let id: String
        let title: String
        let value: String
        let icon: String
    }

    private let columns = DashboardHeaderView.Layout.metricColumns

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metricsGrid(
                metrics: [
                    MetricInfo(
                        id: "total", title: "Total", value: total,
                        icon: "hourglass",
                    ),
                    MetricInfo(
                        id: "monthly", title: "Este mes", value: monthly,
                        icon: "calendar.badge.clock",
                    ),
                    MetricInfo(
                        id: "weekly", title: "Esta semana", value: weekly,
                        icon: "chart.bar",
                    ),
                    MetricInfo(
                        id: "daily", title: "Hoy", value: daily,
                        icon: "sun.max",
                    ),
                ],
                compact: false,
            )
            metricsGrid(
                metrics: [
                    MetricInfo(
                        id: "total", title: "Total", value: total,
                        icon: "hourglass",
                    ),
                    MetricInfo(
                        id: "monthly", title: "Mes", value: monthly,
                        icon: "calendar.badge.clock",
                    ),
                    MetricInfo(
                        id: "weekly", title: "Semana", value: weekly,
                        icon: "chart.bar",
                    ),
                    MetricInfo(
                        id: "daily", title: "Hoy", value: daily,
                        icon: "sun.max",
                    ),
                ],
                compact: true,
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard-metrics")
    }

    private func metricsGrid(metrics: [MetricInfo], compact: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: DashboardHeaderView.Layout.metricSpacing) {
            ForEach(metrics) { metric in
                MetricTile(
                    title: metric.title,
                    value: metric.value,
                    icon: metric.icon,
                    compact: compact,
                )
            }
        }
    }

    struct MetricTile: View {
        let title: String
        let value: String
        let icon: String
        let compact: Bool

        private var titleFont: Font {
            .system(size: compact ? 8.5 : 9.5, weight: .semibold)
        }

        private var valueFont: Font {
            .system(size: compact ? 12 : 14, weight: .semibold)
        }

        private var tilePadding: CGFloat { compact ? 7 : 7 }
        private var minHeight: CGFloat {
            compact
                ? DashboardHeaderView.Layout.compactMetricMinHeight
                : DashboardHeaderView.Layout.metricMinHeight
        }

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                    Text(NSLocalizedString(title, comment: ""))
                        .font(titleFont)
                        .textCase(.uppercase)
                        .tracking(compact ? 0.35 : 0.5)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .allowsTightening(true)
                    Text(value)
                        .font(valueFont)
                        .monospacedDigit()
                        .lineLimit(1)
                        .allowsTightening(true)
                }
            }
            .frame(
                maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight,
                alignment: .bottomLeading,
            )
            .padding(tilePadding)
            .detailInsetStyle(
                cornerRadius: 14,
                strokeOpacity: 0.12,
            )
        }
    }
}
