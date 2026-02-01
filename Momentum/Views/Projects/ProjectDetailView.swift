import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    @Bindable var project: Project
    @State private var usageWindow: UsageWindow = .hour
    let isTrackingActiveForProject: Bool
    let onEdit: (Project) -> Void
    let onDelete: (Project) -> Void
    let onClearActivity: (Project) -> Void
    let onStartTracking: (Project) -> Void
    @State private var showClearActivityDialog = false
    @State private var showDeleteDialog = false
    @State private var stats = ProjectDetailStats.empty
    @State private var lastUsedSnapshot: LastUsedSessionSnapshot?
    @State private var isProjectEmptyState = false
    @State private var sessionSnapshots: [ProjectUsageSummarizer.UsageSessionSnapshot] = []
    @State private var lastRefreshDate: Date?
    @State private var isRefreshing = false
    @State private var showsRefreshIndicator = false
    @State private var refreshIndicatorToken = UUID()
    @State private var refreshCounter = 0

    enum MetricLayout {
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

    private enum RefreshPolicy {
        static let minInterval: TimeInterval = 3
        static let refreshInterval: TimeInterval = 600
        static let indicatorDelay: TimeInterval = 0.4
    }

    init(
        project: Project,
        isTrackingActiveForProject: Bool = false,
        onEdit: @escaping (Project) -> Void = { _ in },
        onDelete: @escaping (Project) -> Void = { _ in },
        onClearActivity: @escaping (Project) -> Void = { _ in },
        onStartTracking: @escaping (Project) -> Void = { _ in },
    ) {
        _project = Bindable(project)
        self.isTrackingActiveForProject = isTrackingActiveForProject
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onClearActivity = onClearActivity
        self.onStartTracking = onStartTracking
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                header
                if shouldShowEmptyState {
                    ProjectEmptyStateView {
                        onStartTracking(project)
                    }
                }
                summarySection
                WeeklySummaryChartView(project: project, refreshToken: refreshCounter)
                ActivityHistorySectionView(project: project, refreshToken: refreshCounter)
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
                            showDeleteDialog = true
                        } label: {
                            Text("Eliminar")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityIdentifier("project-actions-menu")
                    }
                }
            }
            .alert("¿Quieres eliminar todas las sesiones de este proyecto?", isPresented: $showClearActivityDialog) {
                Button("Limpiar actividad", role: .destructive) {
                    onClearActivity(project)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción conserva el proyecto y borra su historial de tiempo.")
            }
            .alert("¿Eliminar este proyecto?", isPresented: $showDeleteDialog) {
                Button("Eliminar proyecto", role: .destructive) {
                    onDelete(project)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminará el proyecto y su historial asociado.")
            }
        }
        .task(id: project.persistentModelID) {
            await refreshIfNeeded(force: true)
            await refreshLoop()
        }
        .task(id: usageWindow) {
            await refreshUsageSummaries()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                Circle()
                    .fill(project.color.gradient)
                    .frame(width: Layout.heroIconSize, height: Layout.heroIconSize)
                    .overlay(
                        ProjectIconGlyph(
                            name: project.iconName,
                            size: heroIconGlyphSize,
                            weight: .semibold,
                            symbolStyle: AnyShapeStyle(.white)
                        ),
                    )
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 26, weight: .semibold))
                    HStack(spacing: 8) {
                        DetailMetaPill(
                            text: stats.lastActivityText,
                            systemImage: "clock",
                        )
                        DetailMetaPill(
                            text: streakPillText,
                            systemImage: "flame.fill",
                            tint: .orange,
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
                HStack(spacing: 8) {
                    Text("Tu progreso en un vistazo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    refreshIndicator
                }
            }

            VStack(alignment: .leading, spacing: Layout.metricSpacing) {
                LazyVGrid(columns: Layout.metricColumns, spacing: Layout.metricSpacing) {
                    MetricCard(title: "Total acumulado", value: stats.totalSeconds.hoursAndMinutesString, subtitle: "Tu dedicación merece ser visible.")
                    MetricCard(title: "Mes", value: stats.monthlySeconds.hoursAndMinutesString, subtitle: "Progreso del mes en curso.")
                    MetricCard(title: "Semana", value: stats.weeklySeconds.hoursAndMinutesString, subtitle: "Constancia en los últimos 7 días.")
                    MetricCard(title: "Hoy", value: stats.dailySeconds.hoursAndMinutesString, subtitle: "Cada minuto cuenta.")
                }
                .frame(maxWidth: Layout.metricGridWidth, alignment: .leading)

                HighlightMetricRow(
                    title: "Racha",
                    value: "\(stats.streakCount) días",
                    subtitle: "Mejor racha: \(stats.longestStreakCount) días.",
                    icon: "flame.fill",
                    tint: .orange,
                )
            }
            .frame(maxWidth: Layout.metricGridWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity,
        )
    }

    private var heroIconGlyphSize: CGFloat {
        EmojiDetector.isEmoji(project.iconName) ? 30 : 24
    }

    private var streakPillText: String {
        let streak = stats.streakCount
        let longest = stats.longestStreakCount
        if streak < 2 {
            return "Mejor racha: \(longest) días"
        }
        return "Racha de \(streak) días · Mejor: \(longest) días"
    }

    private var isProjectEmpty: Bool {
        isProjectEmptyState
    }

    private var shouldShowEmptyState: Bool {
        isProjectEmpty && !isTrackingActiveForProject
    }

    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Contexto asignado")
                    .font(.headline)
                Text("Apps, dominios y archivos que suman tiempo automáticamente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if project.assignedApps.isEmpty, project.assignedDomains.isEmpty, project.assignedFiles.isEmpty {
                Text("Asigna apps, dominios o archivos para que Momentum sume tiempo automáticamente.")
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
                    if !project.assignedFiles.isEmpty {
                        Label("Archivos", systemImage: "doc.text")
                            .font(.subheadline.weight(.medium))
                        AssignedFilesChips(filePaths: project.assignedFiles)
                    }
                }
            }
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity,
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

            let summaries = stats.usageSummaries
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
            strokeOpacity: Layout.cardStrokeOpacity,
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
            if let snapshot = lastUsedSnapshot {
                LastUsedCard(snapshot: snapshot)
            } else {
                Text("Aún no hay sesiones para este proyecto.")
                    .foregroundStyle(.secondary)
            }
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity,
        )
    }

    private var refreshIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Actualizando…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(showsRefreshIndicator ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showsRefreshIndicator)
    }

    @MainActor
    private func refreshIfNeeded(force: Bool) async {
        let now = Date()
        if let lastRefreshDate, !force {
            let elapsed = now.timeIntervalSince(lastRefreshDate)
            if elapsed < RefreshPolicy.minInterval {
                return
            }
            if elapsed < RefreshPolicy.refreshInterval {
                return
            }
        }

        await setRefreshing(true)
        let snapshots = project.sessions.map { session in
            ProjectUsageSummarizer.UsageSessionSnapshot(
                startDate: session.startDate,
                endDate: session.endDate,
                contextKey: session.contextKey,
                title: session.primaryContextLabel,
                subtitle: session.secondaryContextLabel,
                bundleIdentifier: session.bundleIdentifier,
                domain: session.domain,
                filePath: session.filePath,
            )
        }

        sessionSnapshots = snapshots
        stats = ProjectDetailStats(project: project)
        isProjectEmptyState = project.sessions.isEmpty && project.dailySummaries.isEmpty
        lastUsedSnapshot = project.sessions.max(by: { $0.endDate < $1.endDate }).map {
            LastUsedSessionSnapshot(session: $0)
        }
        lastRefreshDate = now
        refreshCounter += 1

        let usageInterval = usageWindow.interval
        let summaries = await Task.detached(priority: .userInitiated) {
            ProjectUsageSummarizer.summaries(
                from: snapshots,
                interval: usageInterval,
                limit: 6,
            )
        }.value
        guard !Task.isCancelled else {
            await setRefreshing(false)
            return
        }
        stats = stats.withUsageSummaries(summaries)
        await setRefreshing(false)
    }

    @MainActor
    private func refreshUsageSummaries() async {
        let snapshots = sessionSnapshots
        guard !snapshots.isEmpty else {
            await refreshIfNeeded(force: true)
            return
        }
        let usageInterval = usageWindow.interval
        let summaries = await Task.detached(priority: .userInitiated) {
            ProjectUsageSummarizer.summaries(
                from: snapshots,
                interval: usageInterval,
                limit: 6,
            )
        }.value
        guard !Task.isCancelled else { return }
        stats = stats.withUsageSummaries(summaries)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(RefreshPolicy.refreshInterval))
            } catch {
                return
            }
            await refreshIfNeeded(force: false)
        }
    }

    @MainActor
    private func setRefreshing(_ refreshing: Bool) async {
        if refreshing {
            isRefreshing = true
            showsRefreshIndicator = false
            let indicatorToken = UUID()
            refreshIndicatorToken = indicatorToken
            Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(RefreshPolicy.indicatorDelay))
                } catch {
                    return
                }
                guard isRefreshing, refreshIndicatorToken == indicatorToken else { return }
                showsRefreshIndicator = true
            }
        } else {
            isRefreshing = false
            showsRefreshIndicator = false
        }
    }
}

private struct ProjectDetailStats {
    let totalSeconds: TimeInterval
    let monthlySeconds: TimeInterval
    let weeklySeconds: TimeInterval
    let dailySeconds: TimeInterval
    let streakCount: Int
    let longestStreakCount: Int
    let lastActivityText: String
    let usageSummaries: [ContextUsageSummary]

    @MainActor
    init(project: Project) {
        totalSeconds = project.totalSeconds
        monthlySeconds = project.monthlySeconds
        weeklySeconds = project.weeklySeconds
        dailySeconds = project.dailySeconds
        streakCount = project.streakCount
        longestStreakCount = project.longestStreakCount
        lastActivityText = project.lastActivityText
        usageSummaries = []
    }

    static let empty = ProjectDetailStats(
        totalSeconds: 0,
        monthlySeconds: 0,
        weeklySeconds: 0,
        dailySeconds: 0,
        streakCount: 0,
        longestStreakCount: 0,
        lastActivityText: "Sin datos recientes",
        usageSummaries: [],
    )

    private init(
        totalSeconds: TimeInterval,
        monthlySeconds: TimeInterval,
        weeklySeconds: TimeInterval,
        dailySeconds: TimeInterval,
        streakCount: Int,
        longestStreakCount: Int,
        lastActivityText: String,
        usageSummaries: [ContextUsageSummary],
    ) {
        self.totalSeconds = totalSeconds
        self.monthlySeconds = monthlySeconds
        self.weeklySeconds = weeklySeconds
        self.dailySeconds = dailySeconds
        self.streakCount = streakCount
        self.longestStreakCount = longestStreakCount
        self.lastActivityText = lastActivityText
        self.usageSummaries = usageSummaries
    }

    func withUsageSummaries(_ summaries: [ContextUsageSummary]) -> ProjectDetailStats {
        ProjectDetailStats(
            totalSeconds: totalSeconds,
            monthlySeconds: monthlySeconds,
            weeklySeconds: weeklySeconds,
            dailySeconds: dailySeconds,
            streakCount: streakCount,
            longestStreakCount: longestStreakCount,
            lastActivityText: lastActivityText,
            usageSummaries: summaries,
        )
    }
}
