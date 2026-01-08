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

    fileprivate enum Layout {
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
