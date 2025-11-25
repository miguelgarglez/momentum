//
//  ContentView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tracker: ActivityTracker
    @Query(sort: \Project.createdAt, order: .forward) private var projects: [Project]

    @State private var selectedProjectID: PersistentIdentifier?
    @State private var isShowingProjectForm = false

    var body: some View {
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
                        }
                        .onDelete(perform: deleteProjects)
                    }
                }
            }
            .navigationTitle("Momentum")
            .toolbar {
                ToolbarItem {
                    Button {
                        tracker.toggleTracking()
                    } label: {
                        Label(
                            trackerStatusLabel,
                            systemImage: tracker.isTrackingEnabled ? "pause.circle" : "play.circle"
                        )
                    }
                    .help("Activa o pausa el tracking automático")
                }

                ToolbarItem {
                    Button {
                        isShowingProjectForm = true
                    } label: {
                        Label("Nuevo proyecto", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selected = selectedProject {
                ProjectDetailView(project: selected)
            } else {
                WelcomeView()
            }
        }
        .onAppear {
            selectedProjectID = projects.first?.persistentModelID
        }
        .sheet(isPresented: $isShowingProjectForm) {
            ProjectFormView { draft in
                let project = Project(
                    name: draft.name,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    assignedApps: draft.assignedApps,
                    assignedDomains: draft.assignedDomains
                )
                modelContext.insert(project)
                try? modelContext.save()
                selectedProjectID = project.persistentModelID
            }
        }
    }

    private var trackerStatusLabel: String {
        tracker.isTrackingEnabled ? "Tracking activo" : "Tracking pausado"
    }

    private func deleteProjects(at offsets: IndexSet) {
        offsets.map { projects[$0] }.forEach(modelContext.delete)
        try? modelContext.save()
        selectedProjectID = projects.first?.persistentModelID
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return projects.first }
        return projects.first(where: { $0.persistentModelID == selectedProjectID })
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

struct DashboardHeaderView: View {
    let projects: [Project]

    private var totalSeconds: TimeInterval {
        projects.reduce(0) { $0 + $1.totalSeconds }
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
            DashboardMetricsView(total: totalSeconds, weekly: weeklySeconds, daily: todaySeconds)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DashboardMetricsView: View {
    let total: TimeInterval
    let weekly: TimeInterval
    let daily: TimeInterval

    var body: some View {
        HStack {
            MetricTile(title: "Total invertido", value: total.hoursAndMinutesString, icon: "hourglass")
            MetricTile(title: "Esta semana", value: weekly.hoursAndMinutesString, icon: "calendar")
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

    init(project: Project) {
        self._project = Bindable(project)
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
        }
    }

    private var header: some View {
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
            Spacer()
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            MetricCard(title: "Total acumulado", value: project.totalSeconds.hoursAndMinutesString, subtitle: "Tu dedicación merece ser visible.")
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
                        WrappingChips(items: project.assignedApps)
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

struct WrappingChips: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
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

    private var summaries: [DailySummary] {
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
                        RoundedRectangle(cornerRadius: 6)
                            .fill(project.color.opacity(summary.seconds == 0 ? 0.15 : 0.8))
                            .frame(height: height(for: summary))
                        Text(summary.label.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func height(for summary: DailySummary) -> CGFloat {
        let ratio = summary.seconds / maxSeconds
        return max(12, CGFloat(ratio) * 120)
    }
}

struct ProjectFormDraft {
    var name = ""
    var colorHex = ProjectPalette.defaultColor.hex
    var iconName = ProjectIcon.spark.systemName
    var selectedAppIDs: Set<String> = []
    var manualApps = ""
    var domains = ""

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
    @State private var draft = ProjectFormDraft()

    let onSave: (ProjectFormDraft) -> Void

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
                    TextField("Dominios (separados por coma)", text: $draft.domains)
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Nuevo proyecto")
            .frame(minWidth: 540, maxWidth: 640)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ProjectTitleField: View {
    @Binding var text: String

    var body: some View {
        TextField(
            "Ej. \"Construir Momentum\"",
            text: $text,
            axis: .vertical
        )
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
    }
}

struct AppAutoTrackingSection: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    @Binding var selection: Set<String>
    @Binding var manualApps: String

    @State private var searchText = ""

    private var selectedApps: [InstalledApp] {
        selection.compactMap { appCatalog.app(for: $0) }
            .sorted { $0.name < $1.name }
    }

    private var filteredApps: [InstalledApp] {
        let apps = appCatalog.apps
        guard !searchText.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
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

                TextField("Buscar apps", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, selectedApps.isEmpty ? 0 : 4)

                Group {
                    if filteredApps.isEmpty {
                        Text("No encontramos apps que coincidan con la búsqueda.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredApps) { app in
                                    AppSelectionRow(
                                        app: app,
                                        isSelected: selection.contains(app.bundleIdentifier)
                                    ) {
                                        toggle(app.bundleIdentifier)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .frame(minHeight: 160, maxHeight: 260)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.secondary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.secondary.opacity(0.15))
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Bundle IDs adicionales")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("com.ejemplo.app, com.otro.bundle", text: $manualApps)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func toggle(_ identifier: String) {
        if selection.contains(identifier) {
            selection.remove(identifier)
        } else {
            selection.insert(identifier)
        }
    }
}

struct SelectedAppChips: View {
    let apps: [InstalledApp]
    @Binding var selection: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
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

#Preview {
    let container = try! ModelContainer(
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
    container.mainContext.insert(previewProject)

    let tracker = ActivityTracker(modelContainer: container)
    let sampleApps = [
        InstalledApp(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode", url: URL(fileURLWithPath: "/Applications/Xcode.app"), icon: nil),
        InstalledApp(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), icon: nil),
        InstalledApp(bundleIdentifier: "com.apple.Safari", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), icon: nil)
    ]
    let catalog = AppCatalog(searchPaths: [], initialApps: sampleApps)

    return ContentView()
        .environmentObject(tracker)
        .environmentObject(catalog)
        .modelContainer(container)
}
