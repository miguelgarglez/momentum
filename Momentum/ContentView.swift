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

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                ActionPanelView(
                    summary: tracker.statusSummary,
                    isTrackingEnabled: tracker.isTrackingEnabled,
                    onToggleTracking: { tracker.toggleTracking() },
                    onCreateProject: { activeProjectSheet = .create },
                    settingsControl: settingsControlView
                )

                Divider()

                NavigationSplitView {
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
                } detail: {
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
                .navigationTitle("Momentum")
                .onAppear {
                    selectedProjectID = projects.first?.persistentModelID
                }
                .sheet(item: $activeProjectSheet, content: sheetContent)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: toast)
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
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
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
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
        .background(.regularMaterial)
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
        .padding()
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
    @State private var usageWindow: UsageWindow = .hour
    let onEdit: (Project) -> Void
    let onDelete: (Project) -> Void
    let onClearActivity: (Project) -> Void
    @State private var showClearActivityDialog = false

    init(
        project: Project,
        onEdit: @escaping (Project) -> Void = { _ in },
        onDelete: @escaping (Project) -> Void = { _ in },
        onClearActivity: @escaping (Project) -> Void = { _ in }
    ) {
        self._project = Bindable(project)
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onClearActivity = onClearActivity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricGrid
                WeeklySummaryChartView(project: project)
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
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: project.iconName)
                            .font(.title2)
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.title2.bold())
                    Text(project.lastActivityText)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            MetricCard(title: "Total acumulado", value: project.totalSeconds.hoursAndMinutesString, subtitle: "Tu dedicación merece ser visible.")
            MetricCard(title: "Mes", value: project.monthlySeconds.hoursAndMinutesString, subtitle: "Progreso del mes en curso.")
            MetricCard(title: "Semana", value: project.weeklySeconds.hoursAndMinutesString, subtitle: "Constancia en los últimos 7 días.")
            MetricCard(title: "Hoy", value: project.dailySeconds.hoursAndMinutesString, subtitle: "Cada minuto cuenta.")
            MetricCard(title: "Racha", value: "\(project.streakCount) días", subtitle: "Días consecutivos con actividad.")
        }
    }

    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contexto asignado")
                .font(.headline)
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
    }

    private var usageSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Uso por contexto")
                    .font(.headline)
                Spacer()
                Picker("Intervalo", selection: $usageWindow) {
                    ForEach(UsageWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            let summaries = project.contextUsageSummaries(for: usageWindow.interval, limit: 6)
            if summaries.isEmpty {
                Text("Aún no hay registros para este intervalo.")
                    .foregroundStyle(.secondary)
            } else {
                ContextUsageList(summaries: summaries)
            }
        }
    }

    private var lastUsedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Último usado")
                .font(.headline)
            if let session = project.sessions.sorted(by: { $0.endDate > $1.endDate }).first {
                LastUsedCard(session: session)
            } else {
                Text("Aún no hay sesiones para este proyecto.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
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
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
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

struct WeeklySummaryChartView: View {
    let project: Project
    @State private var hoveredDate: Date?
    private let chartHeight: CGFloat = 120

    private var summaries: [DailySummaryPoint] {
        project.recentDailySummaries()
    }

    private var maxSeconds: TimeInterval {
        max(summaries.map(\.seconds).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Últimos 7 días")
                .font(.headline)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(summaries, id: \.date) { summary in
                    VStack {
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(project.color.opacity(summary.seconds == 0 ? 0.15 : 0.8))
                                .frame(height: height(for: summary))
                                .overlay(alignment: .top) {
                                    if hoveredDate == summary.date {
                                        ChartTooltipView(text: summary.seconds.minutesOrHoursMinutesString)
                                            .offset(y: -8)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                        }
                        .frame(height: chartHeight)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredDate = hovering ? summary.date : nil
                        }
                        .animation(.easeInOut(duration: 0.12), value: hoveredDate)
                        Text(summary.label.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func height(for summary: DailySummaryPoint) -> CGFloat {
        let ratio = summary.seconds / maxSeconds
        return max(12, CGFloat(ratio) * chartHeight)
    }
}

private struct ChartTooltipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
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
