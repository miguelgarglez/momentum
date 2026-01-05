//
//  ContentView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI
import SwiftData
import Combine
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tracker: ActivityTracker
    @Query(
        sort: [
            SortDescriptor(\Project.createdAt, order: .forward)
        ]
    ) private var projects: [Project]
    @Query(sort: [SortDescriptor(\PendingTrackingSession.endDate, order: .reverse)])
    private var pendingSessions: [PendingTrackingSession]

    @State private var selectedProjectID: PersistentIdentifier?
    @State private var activeProjectSheet: ProjectSheet?
    @State private var showConflictSheet = false
    @State private var toast: ToastMessage?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private enum Layout {
        static let actionPanelWidth: CGFloat = 84
        static let toastAnimation = Animation.spring(response: 0.3, dampingFraction: 0.85)
        static let sidebarInset: CGFloat = 8
        static let sidebarCornerRadius: CGFloat = 18
        static let sidebarBorderOpacity: Double = 0.12
        static let collapsedDetailLeadingPadding: CGFloat = actionPanelWidth + sidebarInset * 2
        static let sidebarMinWidth: CGFloat = 350
        static let sidebarIdealWidth: CGFloat = 400
        static let sidebarMaxWidth: CGFloat = 450
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                HStack(spacing: 0) {
                    actionPanel
                    Divider()
                    sidebarList
                }
                .navigationSplitViewColumnWidth(
                    min: Layout.sidebarMinWidth,
                    ideal: Layout.sidebarIdealWidth,
                    max: Layout.sidebarMaxWidth
                )
                .background(.regularMaterial)
            } detail: {
                detailContent
                    .padding(.leading, columnVisibility == .detailOnly ? Layout.collapsedDetailLeadingPadding : 0)
            }
            .navigationTitle("Momentum")
            .onAppear {
                selectedProjectID = projects.first?.persistentModelID
            }
            .sheet(item: $activeProjectSheet, content: sheetContent)
            .overlay(alignment: .leading) {
                if columnVisibility == .detailOnly {
                    sidebarChrome {
                        actionPanel
                    }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            if let toast {
                ToastView(message: toast.message, style: toast.style)
                    .padding(.bottom, 24)
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topLeading) {
            if !pendingConflicts.isEmpty {
                PendingConflictBanner(count: pendingConflicts.count) {
                    showConflictSheet = true
                }
                .padding(.top, 18)
                .padding(.leading, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Layout.toastAnimation, value: toast)
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .statusItemOpenProject)) { notification in
            guard let identifier = notification.userInfo?[StatusItemUserInfoKey.projectID] as? PersistentIdentifier else { return }
            selectedProjectID = identifier
        }
#endif
        .sheet(isPresented: $showConflictSheet) {
            PendingConflictResolutionView(
                pendingSessions: pendingSessions,
                projects: projects
            )
            .environmentObject(tracker)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selected = selectedProject {
            ProjectDetailView(
                project: selected,
                onEdit: { activeProjectSheet = .edit($0) },
                onDelete: { deleteProject($0) },
                onClearActivity: { clearActivity(for: $0) }
            )
        } else {
            WelcomeView()
        }
    }

    private var actionPanel: some View {
        ActionPanelView(
            summary: tracker.statusSummary,
            isTrackingEnabled: tracker.isTrackingEnabled,
            onToggleTracking: { tracker.toggleTracking() },
            onCreateProject: { activeProjectSheet = .create },
            settingsControl: settingsControlView
        )
        .frame(width: Layout.actionPanelWidth, alignment: .bottomLeading)
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func sidebarChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: Layout.sidebarCornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.sidebarCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(Layout.sidebarBorderOpacity), lineWidth: 1)
            )
            .padding(.horizontal, Layout.sidebarInset)
            .padding(.bottom, Layout.sidebarInset)
            .padding(.top, Layout.sidebarInset)
            .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebarList: some View {
        List(selection: $selectedProjectID) {
            if !projects.isEmpty {
                Section {
                    DashboardHeaderView(projects: projects)
                        .listRowInsets(.init(top: 12, leading: 12, bottom: 12, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            }

            Section("Tus proyectos") {
                if projects.isEmpty {
                    EmptyProjectsView()
                } else {
                    ForEach(projects) { project in
                        ProjectRowView(project: project)
                            .tag(project.persistentModelID)
                            .contextMenu {
                                Button("Editar") {
                                    activeProjectSheet = .edit(project)
                                }
                                Button("Limpiar actividad", role: .destructive) {
                                    clearActivity(for: project)
                                }
                                Button("Eliminar", role: .destructive) {
                                    deleteProject(project)
                                }
                            }
                    }
                    .onDelete(perform: deleteProjects)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }


    @ViewBuilder
    private func sheetContent(for sheet: ProjectSheet) -> some View {
        switch sheet {
        case .create:
            ProjectFormView { draft in
                let project = Project(
                    name: draft.name,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    assignedApps: draft.assignedApps,
                    assignedDomains: draft.assignedDomains
                )
                modelContext.insert(project)
                do {
                    try modelContext.save()
                    selectedProjectID = project.persistentModelID
                    showToast("Proyecto creado", style: .success)
                } catch {
                    showToast("No pudimos crear el proyecto", style: .error)
                }
            }
        case .edit(let project):
            ProjectFormView(project: project) { draft in
                project.apply(draft: draft)
                do {
                    try modelContext.save()
                    showToast("Proyecto actualizado", style: .success)
                } catch {
                    showToast("No pudimos guardar los cambios", style: .error)
                }
            }
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        let targets = offsets.map { projects[$0] }
        targets.forEach(modelContext.delete)
        do {
            try modelContext.save()
            selectedProjectID = projects.first?.persistentModelID
            showToast("Proyecto eliminado", style: .success)
        } catch {
            showToast("No pudimos eliminar el proyecto", style: .error)
        }
    }

    private func deleteProject(_ project: Project) {
        modelContext.delete(project)
        do {
            try modelContext.save()
            selectedProjectID = projects.first?.persistentModelID
            showToast("Proyecto eliminado", style: .success)
        } catch {
            showToast("No pudimos eliminar el proyecto", style: .error)
        }
    }

    private func clearActivity(for project: Project) {
        let sessions = project.sessions
        sessions.forEach { session in
            modelContext.delete(session)
        }
        do {
            try modelContext.save()
            showToast("Actividad limpiada", style: .success)
        } catch {
            showToast("No pudimos limpiar la actividad", style: .error)
        }
    }

    private func showToast(_ message: String, style: ToastMessage.Style = .success) {
        let newToast = ToastMessage(message: message, style: style)
        toast = newToast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toast?.id == newToast.id {
                toast = nil
            }
        }
    }

#if os(macOS)
    private func openSettingsWindow() {
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
#else
    private func openSettingsWindow() {}
#endif

    private var settingsControlView: AnyView {
#if os(macOS)
        if #available(macOS 14.0, *) {
            return AnyView(
                SettingsLink {
                    ActionPanelIcon(systemName: "gearshape", tint: .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes")
            )
        } else {
            return AnyView(
                Button(action: openSettingsWindow) {
                    ActionPanelIcon(systemName: "gearshape", tint: .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes")
            )
        }
#else
        return AnyView(
            Button(action: openSettingsWindow) {
                ActionPanelIcon(systemName: "gearshape", tint: .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajustes")
        )
#endif
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return projects.first }
        return projects.first(where: { $0.persistentModelID == selectedProjectID })
    }

    private var pendingConflicts: [PendingConflict] {
        PendingConflict.grouped(from: pendingSessions, projects: projects)
    }
}

private enum ProjectSheet: Identifiable {
    case create
    case edit(Project)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let project):
            return String(project.persistentModelID.hashValue)
        }
    }
}

private struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Revela tu Momentum")
                .font(.title2.weight(.semibold))
            Text("Crea tu primer proyecto para convertir cada minuto en progreso visible.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)
        }
        .padding()
    }
}

private struct EmptyProjectsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sin proyectos aún")
                .font(.headline)
            Text("Añade un proyecto para medir tu dedicación sin fricción.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(project.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: project.iconName)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text("Total \(project.totalSeconds.hoursAndMinutesString) · Hoy \(project.dailySeconds.hoursAndMinutesString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(project.weeklySeconds.hoursAndMinutesString)
                    .font(.headline)
                Text("Semana")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ActionPanelView: View {
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

private struct PendingConflictBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pendiente de asignación")
                    .font(.subheadline.weight(.semibold))
                Text("Tienes \(count) contexto(s) por resolver.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Resolver") {
                action()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("pending-conflict-resolve-button")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-conflict-banner")
    }
}

private struct PendingConflictResolutionView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss

    let pendingSessions: [PendingTrackingSession]
    let projects: [Project]

    @State private var selections: [String: PersistentIdentifier] = [:]

    var body: some View {
        let conflicts = PendingConflict.grouped(from: pendingSessions, projects: projects)

        NavigationStack {
            Group {
                if conflicts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No hay conflictos pendientes.")
                            .font(.headline)
                        Text("Cuando aparezcan, podrás resolverlos aquí.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(conflicts) { conflict in
                                PendingConflictRow(
                                    conflict: conflict,
                                    selection: Binding(
                                        get: { selections[conflict.id] },
                                        set: { selections[conflict.id] = $0 }
                                    ),
                                    onResolve: { project in
                                        tracker.resolveConflict(context: conflict.context, project: project)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Resolver conflictos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-conflict-sheet")
    }
}

private struct PendingConflictRow: View {
    let conflict: PendingConflict
    @Binding var selection: PersistentIdentifier?
    let onResolve: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.title)
                        .font(.headline)
                    if let subtitle = conflict.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(conflict.totalSeconds.hoursAndMinutesString)
                    .font(.subheadline.weight(.semibold))
            }

            Picker("Proyecto", selection: $selection) {
                ForEach(conflict.candidates) { project in
                    Text(project.name)
                        .tag(project.persistentModelID)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("pending-conflict-project-picker-\(conflict.id)")

            Button("Asignar") {
                guard let selection,
                      let project = conflict.candidates.first(where: { $0.persistentModelID == selection }) else { return }
                onResolve(project)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection == nil)
            .accessibilityIdentifier("pending-conflict-assign-button-\(conflict.id)")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-conflict-row-\(conflict.id)")
        .onAppear {
            if selection == nil {
                selection = conflict.candidates.first?.persistentModelID
            }
        }
    }
}

private struct PendingConflict: Identifiable {
    let id: String
    let context: AssignmentContext
    let title: String
    let subtitle: String?
    let totalSeconds: TimeInterval
    let candidates: [Project]

    static func grouped(from sessions: [PendingTrackingSession], projects: [Project]) -> [PendingConflict] {
        let grouped = Dictionary(grouping: sessions) { "\($0.contextType)::\($0.contextValue)" }

        return grouped.compactMap { key, items in
            guard let first = items.first else { return nil }
            let type = AssignmentContextType(rawValue: first.contextType) ?? .app
            let context = AssignmentContext(type: type, value: first.contextValue)
            let candidates = projects.filter { project in
                switch type {
                case .app:
                    return project.matches(appBundleIdentifier: first.contextValue)
                case .domain:
                    return project.matches(domain: first.contextValue)
                }
            }
            guard !candidates.isEmpty else { return nil }
            let totalSeconds = items.reduce(0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate)) }
            let title: String
            let subtitle: String?
            switch type {
            case .app:
                title = first.appName
                subtitle = first.bundleIdentifier ?? first.contextValue
            case .domain:
                title = first.contextValue
                subtitle = first.appName
            }

            return PendingConflict(
                id: key,
                context: context,
                title: title,
                subtitle: subtitle,
                totalSeconds: totalSeconds,
                candidates: candidates
            )
        }
        .sorted { $0.totalSeconds > $1.totalSeconds }
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

private struct ActionPanelIcon: View {
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

private struct ToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case error
    }

    let id = UUID()
    let message: String
    let style: Style
}

private struct ToastView: View {
    let message: String
    let style: ToastMessage.Style

    private var iconName: String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch style {
        case .success: return .green
        case .error: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(tint)
            Text(message)
                .font(.callout)
                .bold()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 10, x: 0, y: 4)
    }
}

struct DashboardHeaderView: View {
    let projects: [Project]

    private var totalSeconds: TimeInterval {
        projects.reduce(0) { $0 + $1.totalSeconds }
    }

    private var monthlySeconds: TimeInterval {
        projects.reduce(0) { $0 + $1.monthlySeconds }
    }

    private var weeklySeconds: TimeInterval {
        projects.reduce(0) { $0 + $1.weeklySeconds }
    }

    private var todaySeconds: TimeInterval {
        projects.reduce(0) { $0 + $1.dailySeconds }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mide tu progreso, no tu productividad.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DashboardMetricsView(
                total: totalSeconds,
                monthly: monthlySeconds,
                weekly: weeklySeconds,
                daily: todaySeconds
            )
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DashboardMetricsView: View {
    let total: TimeInterval
    let monthly: TimeInterval
    let weekly: TimeInterval
    let daily: TimeInterval

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            MetricTile(title: "Total invertido", value: total.hoursAndMinutesString, icon: "hourglass")
            MetricTile(title: "Este mes", value: monthly.hoursAndMinutesString, icon: "calendar.badge.clock")
            MetricTile(title: "Esta semana", value: weekly.hoursAndMinutesString, icon: "chart.bar")
            MetricTile(title: "Hoy", value: daily.hoursAndMinutesString, icon: "sun.max")
        }
    }

    struct MetricTile: View {
        let title: String
        let value: String
        let icon: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Query private var recentSessions: [TrackingSession]
    @State private var usageWindow: UsageWindow = .hour
    let onEdit: (Project) -> Void
    let onDelete: (Project) -> Void
    let onClearActivity: (Project) -> Void
    @State private var showClearActivityDialog = false
    private enum Layout {
        static let sectionSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 18
        static let cardCornerRadius: CGFloat = 18
        static let cardStrokeOpacity: Double = 0.08
        static let heroIconSize: CGFloat = 64
        static let metricColumns: [GridItem] = [
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        static let metricSpacing: CGFloat = 14
        static let insetCornerRadius: CGFloat = 12
    }

    init(
        project: Project,
        onEdit: @escaping (Project) -> Void = { _ in },
        onDelete: @escaping (Project) -> Void = { _ in },
        onClearActivity: @escaping (Project) -> Void = { _ in }
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
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                header
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
                            text: "\(project.streakCount) días de racha",
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

            LazyVGrid(columns: Layout.metricColumns, spacing: Layout.metricSpacing) {
                MetricCard(title: "Total acumulado", value: project.totalSeconds.hoursAndMinutesString, subtitle: "Tu dedicación merece ser visible.")
                MetricCard(title: "Mes", value: project.monthlySeconds.hoursAndMinutesString, subtitle: "Progreso del mes en curso.")
                MetricCard(title: "Semana", value: project.weeklySeconds.hoursAndMinutesString, subtitle: "Constancia en los últimos 7 días.")
                MetricCard(title: "Hoy", value: project.dailySeconds.hoursAndMinutesString, subtitle: "Cada minuto cuenta.")
            }

            HighlightMetricRow(
                title: "Racha",
                value: "\(project.streakCount) días",
                subtitle: "Días consecutivos con actividad.",
                icon: "flame.fill",
                tint: .orange
            )
        }
        .detailCardStyle(
            padding: Layout.cardPadding,
            cornerRadius: Layout.cardCornerRadius,
            strokeOpacity: Layout.cardStrokeOpacity
        )
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
        }
        .padding(12)
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

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
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
            let start = now.addingTimeInterval(-3600)
            return DateInterval(start: start, end: now)
        case .day:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return DateInterval(start: start, end: now)
        }
    }
}

enum ActivityRange: String, CaseIterable, Identifiable {
    case week
    case month
    case quarter
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Semana"
        case .month: return "Mes"
        case .quarter: return "Trimestre"
        case .year: return "Año"
        }
    }

    var interval: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: now)
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: now)
        case .quarter:
            let start = calendar.date(byAdding: .day, value: -90, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: now)
        case .year:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let start = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
            return DateInterval(start: start, end: now)
        }
    }

    var barWidth: CGFloat {
        switch self {
        case .week: return 28
        case .month: return 14
        case .quarter: return 18
        case .year: return 24
        }
    }
}

struct WeeklySummaryChartView: View {
    let project: Project
    @State private var hoveredDate: Date?
    @State private var range: ActivityRange = .month
    @State private var points: [DailySummaryPoint] = []
    @State private var buckets: [ActivityBucket] = []
    private let chartHeight: CGFloat = 120

    private var maxSeconds: TimeInterval {
        let values = buckets.map(\.seconds)
        return max(values.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            chartView
            footerView
        }
        .detailCardStyle(
            padding: 16,
            cornerRadius: 18,
            strokeOpacity: 0.08
        )
        .task(id: refreshKey) {
            refreshData()
        }
    }

    private var headerView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleBlock(alignment: .leading, textAlignment: .leading)
                Spacer()
                rangePicker
            }
            VStack(spacing: 10) {
                titleBlock(alignment: .center, textAlignment: .center)
                rangePicker
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func titleBlock(alignment: HorizontalAlignment, textAlignment: TextAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(titleText)
                .font(.headline)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rangePicker: some View {
        Picker("Rango", selection: $range) {
            ForEach(ActivityRange.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)
        .labelsHidden()
        .accessibilityLabel("Rango")
    }

    private var chartView: some View {
        ActivityBarsRow(
            project: project,
            buckets: buckets,
            chartHeight: chartHeight,
            maxSeconds: maxSeconds,
            hoveredDate: $hoveredDate,
            range: range
        )
    }

    private var footerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summariesTotalText)
                    .font(.subheadline.weight(.semibold))
                Text("\(activeDays) días activos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var summariesTotalText: String {
        let totalSeconds = points.reduce(0) { $0 + $1.seconds }
        return totalSeconds.hoursAndMinutesString
    }

    private var activeDays: Int {
        points.filter { $0.seconds > 0 }.count
    }

    private var titleText: String {
        switch range {
        case .week:
            return "Últimos 7 días"
        case .month:
            return "Últimos 30 días"
        case .quarter:
            return "Último trimestre"
        case .year:
            return "Último año"
        }
    }

    private var subtitleText: String {
        switch range {
        case .week:
            return "Actividad reciente y consistencia."
        case .month:
            return "Últimos 30 días en detalle."
        case .quarter:
            return "Semanas del último trimestre."
        case .year:
            return "Meses del último año."
        }
    }

    private func aggregate(
        points: [DailySummaryPoint],
        calendar: Calendar,
        by component: Calendar.Component
    ) -> [AggregatedBucket] {
        var totals: [Date: TimeInterval] = [:]
        for point in points {
            guard let bucketStart = calendar.dateInterval(of: component, for: point.date)?.start else { continue }
            totals[bucketStart, default: 0] += point.seconds
        }

        let bucketStarts = bucketDates(for: range, calendar: calendar, component: component)
        return bucketStarts.map { date in
            AggregatedBucket(date: date, seconds: totals[date, default: 0], totalCount: bucketStarts.count)
        }
    }

    private func refreshData() {
        let points = project.dailySummaries(in: range.interval)
        self.points = points
        self.buckets = buildBuckets(from: points)
    }

    private func buildBuckets(from points: [DailySummaryPoint]) -> [ActivityBucket] {
        let calendar = Calendar.current
        let locale = Locale.current
        switch range {
        case .week:
            return points.enumerated().map { _, point in
                ActivityBucket(
                    date: point.date,
                    seconds: point.seconds,
                    label: point.label.uppercased(),
                    showsLabel: true
                )
            }
        case .month:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "d"
            return points.enumerated().map { index, point in
                ActivityBucket(
                    date: point.date,
                    seconds: point.seconds,
                    label: formatter.string(from: point.date),
                    showsLabel: index % 5 == 0 || index == points.count - 1
                )
            }
        case .quarter:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "d/M"
            let aggregated = aggregate(points: points, calendar: calendar, by: .weekOfYear)
            return aggregated.enumerated().map { index, entry in
                ActivityBucket(
                    date: entry.date,
                    seconds: entry.seconds,
                    label: formatter.string(from: entry.date),
                    showsLabel: index == 0 || index == aggregated.count - 1 || index % 2 == 0
                )
            }
        case .year:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "MMM"
            let aggregated = aggregate(points: points, calendar: calendar, by: .month)
            return aggregated.map { entry in
                ActivityBucket(
                    date: entry.date,
                    seconds: entry.seconds,
                    label: formatter.string(from: entry.date).uppercased(),
                    showsLabel: true
                )
            }
        }
    }

    private func bucketDates(for range: ActivityRange, calendar: Calendar, component: Calendar.Component) -> [Date] {
        let interval = range.interval
        let start = calendar.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        var dates: [Date] = []
        var cursor = start
        let step: DateComponents
        switch component {
        case .weekOfYear:
            step = DateComponents(day: 7)
        case .month:
            step = DateComponents(month: 1)
        default:
            step = DateComponents(day: 1)
        }
        while cursor < interval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: step, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private struct AggregatedBucket {
        let date: Date
        let seconds: TimeInterval
        let totalCount: Int
    }

    private var refreshKey: String {
        "\(range.rawValue)-\(project.dailySummaries.count)"
    }
}

private struct ActivityBarsRow: View {
    let project: Project
    let buckets: [ActivityBucket]
    let chartHeight: CGFloat
    let maxSeconds: TimeInterval
    @Binding var hoveredDate: Date?
    let range: ActivityRange
    @State private var availableWidth: CGFloat = 0

    private let tooltipPadding: CGFloat = 12
    private let labelHeight: CGFloat = 18

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            let barWidth = barWidth(for: availableWidth)
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(Array(buckets.enumerated()), id: \.element.date) { index, summary in
                    ActivityBarView(
                        project: project,
                        summary: summary,
                        chartHeight: chartHeight,
                        maxSeconds: maxSeconds,
                        hoveredDate: $hoveredDate,
                        label: label(for: summary),
                        isToday: isToday(summary.date),
                        barWidth: barWidth,
                        labelHeight: labelHeight,
                        tooltipAlignment: tooltipAlignment(for: index)
                    )
                    .frame(width: barWidth)
                    .zIndex(hoveredDate == summary.date ? 1 : 0)
                }
            }
            .frame(minWidth: max(availableWidth, contentWidth(for: availableWidth)), alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, tooltipPadding)
        }
        .scrollDisabled(!needsScroll)
        .frame(height: chartHeight + labelHeight + tooltipPadding)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func label(for summary: ActivityBucket) -> String {
        if range == .week, isToday(summary.date) {
            return "HOY"
        }
        return summary.label.uppercased()
    }

    private var barSpacing: CGFloat {
        range == .week ? 12 : 10
    }

    private func barWidth(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return range.barWidth }
        let count = CGFloat(max(buckets.count, 1))
        let totalSpacing = barSpacing * (count - 1)
        let usable = max(availableWidth - totalSpacing - 8, range.barWidth * count)
        return max(range.barWidth, usable / count)
    }

    private func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(buckets.count, 1))
        let barWidth = barWidth(for: availableWidth)
        let totalSpacing = barSpacing * (count - 1)
        return barWidth * count + totalSpacing
    }

    private var needsScroll: Bool {
        contentWidth(for: availableWidth) > availableWidth
    }

    private func tooltipAlignment(for index: Int) -> Alignment {
        if index == 0 {
            return .topLeading
        }
        if index == buckets.count - 1 {
            return .topTrailing
        }
        return .top
    }
}

private struct ActivityBarView: View {
    let project: Project
    let summary: ActivityBucket
    let chartHeight: CGFloat
    let maxSeconds: TimeInterval
    @Binding var hoveredDate: Date?
    let label: String
    let isToday: Bool
    let barWidth: CGFloat
    let labelHeight: CGFloat
    let tooltipAlignment: Alignment

    var body: some View {
        VStack {
            barView
            labelView
        }
        .frame(maxWidth: .infinity)
    }

    private var barView: some View {
        VStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 6)
                .fill(barFillColor)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(barStrokeColor, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    if isHovered {
                        ChartTooltipView(text: summary.seconds.minutesOrHoursMinutesString)
                            .frame(width: barWidth, alignment: tooltipAlignment)
                            .offset(y: -8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(1)
                    }
                }
        }
        .zIndex(isHovered ? 1 : 0)
        .frame(height: chartHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredDate = hovering ? summary.date : nil
        }
        .animation(.easeInOut(duration: 0.12), value: hoveredDate)
    }

    private var labelView: some View {
        Group {
            if summary.showsLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.tail)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(height: labelHeight)
    }

    private var isHovered: Bool {
        hoveredDate == summary.date
    }

    private var barFillColor: Color {
        project.color.opacity(summary.seconds == 0 ? 0.12 : 0.75)
    }

    private var barStrokeColor: Color {
        isToday ? project.color.opacity(0.7) : .clear
    }

    private var height: CGFloat {
        let ratio = summary.seconds / max(maxSeconds, 1)
        return max(12, CGFloat(ratio) * chartHeight)
    }
}

struct ActivityHistorySectionView: View {
    let project: Project
    @State private var selectedYear: Int = Calendar.current.component(.year, from: .now)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heatmap anual")
                    .font(.headline)
                Text("Distribución diaria de tu actividad por año.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ActivityHeatmapView(project: project, selectedYear: $selectedYear)
        }
        .detailCardStyle(
            padding: 16,
            cornerRadius: 18,
            strokeOpacity: 0.08
        )
    }
}

private struct ActivityBucket: Identifiable {
    let date: Date
    let seconds: TimeInterval
    let label: String
    let showsLabel: Bool

    var id: Date { date }
}

struct ActivityHeatmapView: View {
    let project: Project
    @Binding var selectedYear: Int
    @State private var hoveredDay: Date?
    @State private var days: [HeatmapDay] = []
    @State private var thresholds: [TimeInterval] = [0, 0, 0]

    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 4

    private var weeks: [[HeatmapDay]] {
        stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heatmap")
                        .font(.subheadline.weight(.semibold))
                    Text(yearTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Año", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        VStack(spacing: spacing) {
                            monthLabelView(for: weekIndex)
                            VStack(spacing: spacing) {
                                ForEach(weeks[weekIndex]) { day in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color(for: day))
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(
                                                    hoveredDay == day.date && day.seconds > 0 ? project.color.opacity(0.7) : .clear,
                                                    lineWidth: 1
                                                )
                                        )
                                        .overlay(alignment: .top) {
                                            if hoveredDay == day.date, day.isInRange, day.seconds > 0 {
                                                ChartTooltipView(text: day.seconds.minutesOrHoursMinutesString)
                                                    .offset(x: tooltipOffset(for: weekIndex), y: -8)
                                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onHover { hovering in
                                            hoveredDay = hovering ? day.date : nil
                                        }
                                        .animation(.easeInOut(duration: 0.12), value: hoveredDay)
                                }
                            }
                        }
                        .frame(width: cellSize)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            HStack(spacing: 6) {
                Text("Menos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: index))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("Más")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: refreshKey) { refreshDays() }
    }

    private var yearTitle: String {
        String(selectedYear)
    }

    private func color(for day: HeatmapDay) -> Color {
        guard day.isInRange else {
            return Color.primary.opacity(0.05)
        }
        return color(for: intensity(for: day.seconds))
    }

    private func color(for intensity: Int) -> Color {
        switch intensity {
        case 0: return Color.primary.opacity(0.08)
        case 1: return project.color.opacity(0.25)
        case 2: return project.color.opacity(0.45)
        case 3: return project.color.opacity(0.65)
        default: return project.color.opacity(0.85)
        }
    }

    private func intensity(for seconds: TimeInterval) -> Int {
        HeatmapIntensityCalculator.intensity(for: seconds, thresholds: thresholds)
    }

    private func refreshDays() {
        ensureSelectedYearIsAvailable()
        let interval = yearInterval(for: selectedYear)
        let calendar = Calendar.current
        let rangeStart = DailySummary.normalize(interval.start)
        let rangeEnd = DailySummary.normalize(interval.end)
        let gridStart = startOfWeek(for: rangeStart, calendar: calendar)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: rangeEnd) ?? rangeEnd
        let gridEnd = calendar.date(byAdding: .day, value: 7, to: startOfWeek(for: lastDay, calendar: calendar)) ?? rangeEnd

        let points = project.dailySummaries(in: interval)
        let totals = Dictionary(uniqueKeysWithValues: points.map { ($0.date, $0.seconds) })

        var days: [HeatmapDay] = []
        var cursor = gridStart
        while cursor < gridEnd {
            let isInRange = cursor >= rangeStart && cursor < rangeEnd
            let seconds = isInRange ? totals[cursor, default: 0] : 0
            days.append(HeatmapDay(date: cursor, seconds: seconds, isInRange: isInRange))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }

        self.days = days
        let values = days.filter { $0.isInRange && $0.seconds > 0 }.map(\.seconds)
        self.thresholds = HeatmapIntensityCalculator.thresholds(for: values)
    }

    private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: calendar.startOfDay(for: date)) ?? date
    }

    private var refreshKey: String {
        "\(selectedYear)-\(project.dailySummaries.count)"
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        var years: Set<Int> = []
        if !project.dailySummaries.isEmpty {
            for summary in project.dailySummaries {
                years.insert(calendar.component(.year, from: summary.date))
            }
        } else {
            for session in project.sessions {
                years.insert(calendar.component(.year, from: session.startDate))
                years.insert(calendar.component(.year, from: session.endDate))
            }
        }
        if years.isEmpty {
            years.insert(calendar.component(.year, from: .now))
        }
        return years.sorted(by: >)
    }

    private func yearInterval(for year: Int) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func ensureSelectedYearIsAvailable() {
        guard !availableYears.contains(selectedYear) else { return }
        selectedYear = availableYears.first ?? Calendar.current.component(.year, from: .now)
    }

    private func tooltipOffset(for weekIndex: Int) -> CGFloat {
        let lastIndex = max(weeks.count - 1, 0)
        if weekIndex == 0 { return 12 }
        if weekIndex == lastIndex { return -12 }
        return 0
    }

    private func monthLabelView(for weekIndex: Int) -> some View {
        let label = monthLabel(for: weekIndex)
        return Group {
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(height: cellSize)
    }

    private func monthLabel(for weekIndex: Int) -> String? {
        guard weekIndex < weeks.count else { return nil }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM"
        for day in weeks[weekIndex] where day.isInRange {
            if calendar.component(.day, from: day.date) == 1 {
                return formatter.string(from: day.date).uppercased()
            }
        }
        return nil
    }
}

private struct HeatmapDay: Identifiable {
    let date: Date
    let seconds: TimeInterval
    let isInRange: Bool

    var id: Date { date }
}

private struct ChartTooltipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.8))
            )
            .accessibilityLabel("Tiempo: \(text)")
    }
}

private struct DetailMetaPill: View {
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

private struct HighlightMetricRow: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
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

private extension View {
    func detailCardStyle(
        padding: CGFloat = 18,
        cornerRadius: CGFloat = 18,
        strokeOpacity: Double = 0.08
    ) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1)
            )
    }

    func detailInsetStyle(
        cornerRadius: CGFloat = 12,
        strokeOpacity: Double = 0.12
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}

struct ProjectFormDraft {
    var name: String
    var colorHex: String
    var iconName: String
    var selectedAppIDs: Set<String>
    var manualApps: String
    var domains: String

    init(project: Project? = nil) {
        if let project {
            name = project.name
            colorHex = project.colorHex
            iconName = project.iconName
            selectedAppIDs = Set(project.assignedApps)
            manualApps = ""
            domains = project.assignedDomains.joined(separator: ", ")
        } else {
            name = ""
            colorHex = ProjectPalette.defaultColor.hex
            iconName = ProjectIcon.spark.systemName
            selectedAppIDs = []
            manualApps = ""
            domains = ""
        }
    }

    var assignedApps: [String] {
        let manual = manualApps
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(selectedAppIDs.union(manual))
            .sorted()
    }

    var assignedDomains: [String] {
        domains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appCatalog: AppCatalog
    @State private var draft: ProjectFormDraft
    private let mode: FormMode

    let onSave: (ProjectFormDraft) -> Void

    init(project: Project? = nil, onSave: @escaping (ProjectFormDraft) -> Void) {
        self.onSave = onSave
        self.mode = project == nil ? .create : .edit
        self._draft = State(initialValue: ProjectFormDraft(project: project))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detalles") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nombre del proyecto")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProjectTitleField(text: $draft.name)
                    }
                    Picker("Icono", selection: $draft.iconName) {
                        ForEach(ProjectIcon.allCases, id: \.self) { icon in
                            Label(icon.displayName, systemImage: icon.systemName)
                                .tag(icon.systemName)
                        }
                    }
                }

                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(ProjectPalette.colors) { paletteColor in
                                Circle()
                                    .fill(Color(hex: paletteColor.hex) ?? .accentColor)
                                    .frame(width: 48, height: 48)
                                    .overlay {
                                        if paletteColor.hex == draft.colorHex {
                                            Image(systemName: "checkmark")
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    .onTapGesture {
                                        draft.colorHex = paletteColor.hex
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                AppAutoTrackingSection(
                    selection: $draft.selectedAppIDs,
                    manualApps: $draft.manualApps
                )

                Section("Dominios") {
#if os(macOS)
                    LTRTextField(
                        text: $draft.domains,
                        placeholder: "Dominios (separados por coma)",
                        accessibilityIdentifier: "project-domains-field"
                    )
                    .macRoundedTextFieldStyle()
                    .padding(.vertical, 4)
#else
                    TextField("Dominios (separados por coma)", text: $draft.domains)
                        .accessibilityIdentifier("project-domains-field")
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 4)
#endif
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(mode == .create ? "Nuevo proyecto" : "Editar proyecto")
            .frame(minWidth: 540, maxWidth: 640)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? "Crear" : "Guardar") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private enum FormMode {
        case create
        case edit
    }
}

struct ProjectTitleField: View {
    @Binding var text: String

    var body: some View {
#if os(macOS)
        LTRTextField(
            text: $text,
            placeholder: "Ej. \"Construir Momentum\"",
            font: NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold),
            allowsMultiline: true,
            accessibilityIdentifier: "project-title-field"
        )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15))
            )
#else
        TextField(
            "Ej. \"Construir Momentum\"",
            text: $text,
            axis: .vertical
        )
        .accessibilityIdentifier("project-title-field")
        .font(.title3.weight(.semibold))
        .textFieldStyle(.plain)
        .multilineTextAlignment(.leading)
        .tint(.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15))
        )
#endif
    }
}

struct AppAutoTrackingSection: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    @Binding var selection: Set<String>
    @Binding var manualApps: String

    @State private var isSelectorPresented = false

    private var selectedApps: [InstalledApp] {
        selection.compactMap { appCatalog.app(for: $0) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Section("Apps instaladas") {
            VStack(alignment: .leading, spacing: 16) {
                if appCatalog.isLoading {
                    ProgressView("Escaneando aplicaciones…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !selectedApps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Asignadas")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        SelectedAppChips(apps: selectedApps, selection: $selection)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        isSelectorPresented.toggle()
                    } label: {
                        Label("Seleccionar apps instaladas", systemImage: "rectangle.stack")
                    }
                    .popover(
                        isPresented: $isSelectorPresented,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        ProjectAppCatalogSelectionPanel(selection: $selection)
                            .frame(width: 360, height: 420)
                            .padding()
                    }
                    .contextMenu {
                        if appCatalog.apps.isEmpty {
                            Text("Catálogo vacío")
                        } else {
                            ForEach(appCatalog.apps.prefix(8)) { app in
                                Button(app.name) {
                                    selection.insert(app.bundleIdentifier)
                                }
                            }
                            if appCatalog.apps.count > 8 {
                                Divider()
                                Text("Abre el selector para ver todas las apps")
                                    .font(.caption)
                            }
                        }
                    }
                }


                VStack(alignment: .leading, spacing: 6) {
                    Text("Bundle IDs adicionales")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
#if os(macOS)
                    LTRTextField(
                        text: $manualApps,
                        placeholder: "com.ejemplo.app, com.otro.bundle"
                    )
                    .macRoundedTextFieldStyle()
#else
                    TextField("com.ejemplo.app, com.otro.bundle", text: $manualApps)
                        .textFieldStyle(.roundedBorder)
#endif
                }
            }
            .padding(.vertical, 4)
        }
    }

}

struct SelectedAppChips: View {
    let apps: [InstalledApp]
    @Binding var selection: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(apps, id: \.self) { app in
                HStack(spacing: 6) {
                    app.icon
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(app.name)
                        .font(.caption)
                        .lineLimit(1)
                    Button {
                        selection.remove(app.bundleIdentifier)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}

private struct ProjectAppCatalogSelectionPanel: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    @Binding var selection: Set<String>
    @State private var searchText: String = ""

    private var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return appCatalog.apps }
        return appCatalog.apps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selecciona apps a incluir")
                .font(.headline)

#if os(macOS)
            LTRTextField(
                text: $searchText,
                placeholder: "Buscar apps"
            )
            .macRoundedTextFieldStyle()
#else
            TextField("Buscar apps", text: $searchText)
                .textFieldStyle(.roundedBorder)
#endif

            if filteredApps.isEmpty {
                Text("No encontramos apps que coincidan con la búsqueda.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredApps) { app in
                            AppSelectionRow(
                                app: app,
                                isSelected: selection.contains(app.bundleIdentifier)
                            ) {
                                toggle(identifier: app.bundleIdentifier)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Text("Haz clic para alternar la asignación. Cierra el panel cuando termines.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(identifier: String) {
        if selection.contains(identifier) {
            selection.remove(identifier)
        } else {
            selection.insert(identifier)
        }
    }
}

struct AppSelectionRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                app.icon
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(Color.secondary.opacity(isSelected ? 0.2 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct ContentViewPreviewWrapper: View {
    let container: ModelContainer
    let tracker: ActivityTracker
    let settings: TrackerSettings
    let catalog: AppCatalog

    init() {
        let schemaContainer = try! ModelContainer(
            for: Project.self,
                 TrackingSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let previewProject = Project(name: "Certificación UX", colorHex: "#A78BFA", iconName: ProjectIcon.book.systemName)
        previewProject.sessions = [
            TrackingSession(
                startDate: .now.addingTimeInterval(-3600),
                endDate: .now.addingTimeInterval(-1800),
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                domain: nil,
                project: previewProject
            )
        ]
        schemaContainer.mainContext.insert(previewProject)

        let previewSettings = TrackerSettings()
        let previewTracker = ActivityTracker(modelContainer: schemaContainer, settings: previewSettings)
        let sampleApps = [
            InstalledApp(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode", url: URL(fileURLWithPath: "/Applications/Xcode.app"), icon: nil),
            InstalledApp(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), icon: nil),
            InstalledApp(bundleIdentifier: "com.apple.Safari", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), icon: nil)
        ]
        let previewCatalog = AppCatalog(searchPaths: [], initialApps: sampleApps)

        self.container = schemaContainer
        self.tracker = previewTracker
        self.settings = previewSettings
        self.catalog = previewCatalog
    }

    var body: some View {
        ContentView()
            .environmentObject(tracker)
            .environmentObject(settings)
            .environmentObject(catalog)
            .modelContainer(container)
    }
}

#Preview {
    ContentViewPreviewWrapper()
}
