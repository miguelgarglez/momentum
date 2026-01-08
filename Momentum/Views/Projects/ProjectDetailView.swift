import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Query private var recentSessions: [TrackingSession]
    @State private var usageWindow: UsageWindow = .hour
    let onEdit: (Project) -> Void
    let onDelete: (Project) -> Void
    let onClearActivity: (Project) -> Void
    let onStartTracking: (Project) -> Void
    @State private var showClearActivityDialog = false

    fileprivate enum MetricLayout {
        static let minHeight: CGFloat = 110
        static let maxWidth: CGFloat = 360
    }

    private enum Layout {
        static let sectionSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 18
        static let cardCornerRadius: CGFloat = 18
        static let cardStrokeOpacity: Double = 0.08
        static let heroIconSize: CGFloat = 64
        static let metricColumns: [GridItem] = [
            GridItem(.flexible(minimum: 0, maximum: MetricLayout.maxWidth), alignment: .bottomLeading),
            GridItem(.flexible(minimum: 0, maximum: MetricLayout.maxWidth), alignment: .bottomLeading),
        ]
        static let metricSpacing: CGFloat = 14
        static let metricGridWidth: CGFloat = MetricLayout.maxWidth * 2 + metricSpacing
        static let insetCornerRadius: CGFloat = 12
    }

    init(
        project: Project,
        onEdit: @escaping (Project) -> Void = { _ in },
        onDelete: @escaping (Project) -> Void = { _ in },
        onClearActivity: @escaping (Project) -> Void = { _ in },
        onStartTracking: @escaping (Project) -> Void = { _ in }
    ) {
        self._project = Bindable(project)
        let projectID = project.persistentModelID
        self._recentSessions = Query(
            filter: #Predicate<TrackingSession> { session in
                session.project?.persistentModelID == projectID
            },
            sort: [SortDescriptor(\TrackingSession.endDate, order: .reverse)]
        )
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onClearActivity = onClearActivity
        self.onStartTracking = onStartTracking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                header
                if isProjectEmpty {
                    ProjectEmptyStateView {
                        onStartTracking(project)
                    }
                }
                summarySection
                WeeklySummaryChartView(project: project)
                ActivityHistorySectionView(project: project)
                assignmentsSection
                usageSummarySection
                lastUsedSection
            }
            .padding()
            .navigationTitle(project.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Editar") { onEdit(project) }
                        Button(role: .destructive) {
                            showClearActivityDialog = true
                        } label: {
                            Text("Limpiar actividad")
                        }
                        Button(role: .destructive) {
                            onDelete(project)
                        } label: {
                            Text("Eliminar")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityIdentifier("project-actions-menu")
                    }
                }
            }
            .confirmationDialog(
                "¿Quieres eliminar todas las sesiones de este proyecto?",
                isPresented: $showClearActivityDialog,
                titleVisibility: .visible
            ) {
                Button("Limpiar actividad", role: .destructive) {
                    onClearActivity(project)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción conserva el proyecto y borra su historial de tiempo.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                Circle()
                    .fill(project.color.gradient)
                    .frame(width: Layout.heroIconSize, height: Layout.heroIconSize)
                    .overlay(
                        Image(systemName: project.iconName)
                            .font(.title2)
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 26, weight: .semibold))
                    HStack(spacing: 8) {
                        DetailMetaPill(
                            text: project.lastActivityText,
                            systemImage: "clock"
                        )
                        DetailMetaPill(
                            text: streakPillText,
                            systemImage: "flame.fill",
                            tint: .orange
                        )
                    }
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }
            Spacer()
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Resumen")
                    .font(.headline)
                Text("Tu progreso en un vistazo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Layout.metricSpacing) {
                LazyVGrid(columns: Layout.metricColumns, spacing: Layout.metricSpacing) {
                    MetricCard(title: "Total acumulado", value: project.totalSeconds.hoursAndMinutesString, subtitle: "Tu dedicación merece ser visible.")
                    MetricCard(title: "Mes", value: project.monthlySeconds.hoursAndMinutesString, subtitle: "Progreso del mes en curso.")
                    MetricCard(title: "Semana", value: project.weeklySeconds.hoursAndMinutesString, subtitle: "Constancia en los últimos 7 días.")
                    MetricCard(title: "Hoy", value: project.dailySeconds.hoursAndMinutesString, subtitle: "Cada minuto cuenta.")
                }
                .frame(maxWidth: Layout.metricGridWidth, alignment: .leading)

                HighlightMetricRow(
                    title: "Racha",
                    value: "\(project.streakCount) días",
                    subtitle: "Mejor racha: \(project.longestStreakCount) días.",
                    icon: "flame.fill",
                    tint: .orange
                )
            }
            .frame(maxWidth: Layout.metricGridWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity
        )
    }

    private var streakPillText: String {
        let streak = project.streakCount
        let longest = project.longestStreakCount
        if streak < 2 {
            return "Mejor racha: \(longest) días"
        }
        return "Racha de \(streak) días · Mejor: \(longest) días"
    }

    private var isProjectEmpty: Bool {
        project.sessions.isEmpty && project.dailySummaries.isEmpty
    }

    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Contexto asignado")
                    .font(.headline)
                Text("Apps y dominios que suman tiempo automáticamente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if project.assignedApps.isEmpty && project.assignedDomains.isEmpty {
                Text("Asigna apps o dominios para que Momentum sume tiempo automáticamente.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !project.assignedApps.isEmpty {
                        Label("Apps", systemImage: "macwindow")
                            .font(.subheadline.weight(.medium))
                        AssignedAppsChips(bundleIdentifiers: project.assignedApps)
                    }
                    if !project.assignedDomains.isEmpty {
                        Label("Dominios", systemImage: "globe")
                            .font(.subheadline.weight(.medium))
                        WrappingChips(items: project.assignedDomains)
                    }
                }
            }
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity
        )
    }

    private var usageSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    usageSummaryHeader(alignment: .leading)
                    Spacer()
                    usageWindowPicker
                }
                VStack(alignment: .center, spacing: 10) {
                    usageSummaryHeader(alignment: .center)
                    usageWindowPicker
                }
            }

            let summaries = project.contextUsageSummaries(for: usageWindow.interval, limit: 6)
            if summaries.isEmpty {
                Text("Aún no hay registros para este intervalo.")
                    .foregroundStyle(.secondary)
            } else {
                ContextUsageList(summaries: summaries)
            }
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity
        )
    }

    private var usageWindowPicker: some View {
        Picker("", selection: $usageWindow) {
            ForEach(UsageWindow.allCases) { window in
                Text(window.title).tag(window)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .accessibilityLabel("Intervalo")
    }

    private func usageSummaryHeader(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text("Uso por contexto")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Text("Distribución del tiempo por app o dominio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private var lastUsedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Último usado")
                .font(.headline)
            if let session = recentSessions.first {
                LastUsedCard(session: session)
            } else {
                Text("Aún no hay sesiones para este proyecto.")
                    .foregroundStyle(.secondary)
            }
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity
        )
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(
            maxWidth: ProjectDetailView.MetricLayout.maxWidth,
            minHeight: ProjectDetailView.MetricLayout.minHeight,
            alignment: .bottomLeading
        )
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12
        )
    }
}

struct ContextUsageList: View {
    let summaries: [ContextUsageSummary]

    var body: some View {
        let maxSeconds = summaries.map { $0.seconds }.max() ?? 1
        VStack(spacing: 12) {
            ForEach(summaries) { summary in
                ContextUsageRow(summary: summary, maxSeconds: maxSeconds)
            }
        }
    }
}

struct ContextUsageRow: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    let summary: ContextUsageSummary
    let maxSeconds: TimeInterval

    private var icon: Image {
        if let bundle = summary.bundleIdentifier,
           let app = appCatalog.app(for: bundle) {
            return app.icon
        }
        return Image(systemName: summary.domain == nil ? "app" : "globe")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                icon
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle = summary.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(summary.seconds.hoursAndMinutesString)
                    .font(.subheadline.bold())
            }

            ProgressView(value: summary.seconds, total: maxSeconds)
                .progressViewStyle(.linear)
        }
        .padding()
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12
        )
    }
}

struct LastUsedCard: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    let session: TrackingSession

    private var title: String { session.primaryContextLabel }
    private var subtitle: String? { session.secondaryContextLabel }

    private var icon: Image {
        if let bundle = session.bundleIdentifier,
           let app = appCatalog.app(for: bundle) {
            return app.icon
        }
        return Image(systemName: session.domain == nil ? "app" : "globe")
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: session.endDate, relativeTo: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                icon
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.bold())
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(session.duration.hoursAndMinutesString)
                    .font(.headline)
            }

            Text("Último registro: \(relativeTime)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12
        )
    }
}

struct AssignedAppsChips: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    let bundleIdentifiers: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(bundleIdentifiers, id: \.self) { identifier in
                chip(for: identifier)
            }
        }
    }

    @ViewBuilder
    private func chip(for identifier: String) -> some View {
        let app = appCatalog.app(for: identifier)
        HStack(spacing: 8) {
            appIcon(for: app)
            Text(app?.name ?? identifier)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .help(app?.bundleIdentifier ?? identifier)
    }

    @ViewBuilder
    private func appIcon(for app: InstalledApp?) -> some View {
        (app?.icon ?? Image(systemName: "app"))
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct WrappingChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }
}

struct HighlightMetricRow: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12
        )
    }
}

struct DetailMetaPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .foregroundStyle(tint)
    }
}

enum UsageWindow: String, CaseIterable, Identifiable {
    case hour
    case day
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: return "1h"
        case .day: return "Hoy"
        case .week: return "7 días"
        }
    }

    var interval: DateInterval {
        let now = Date()
        let calendar = Calendar.current

        switch self {
        case .hour:
            return DateInterval(start: now.addingTimeInterval(-3600), end: now)
        case .day:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, end: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, end: now)
        }
    }
}
