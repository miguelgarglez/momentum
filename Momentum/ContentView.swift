//
//  ContentView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import Combine
import SwiftData
import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var automationPermissionManager: AutomationPermissionManager
    @EnvironmentObject private var trackingSessionManager: TrackingSessionManager
    @Query(
        sort: [
            SortDescriptor(\Project.createdAt, order: .forward),
        ],
    ) private var projects: [Project]
    @Query(sort: [SortDescriptor(\PendingTrackingSession.endDate, order: .reverse)])
    private var pendingSessions: [PendingTrackingSession]

    @State private var selectedProjectID: PersistentIdentifier?
    @State private var activeProjectSheet: ProjectSheet?
    @State private var showConflictSheet = false
    @State private var showManualTrackingSheet = false
    @State private var showAutomationPrompt = false
    @State private var toast: ToastMessage?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var pendingProjectAction: PendingProjectAction?
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    @State private var hasPresentedWelcome = false
    @State private var onboardingTrackingStarter = OnboardingTrackingStarter()

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

    private enum PendingProjectAction: Identifiable {
        case clear(Project)
        case delete(Project)

        var id: String {
            "\(actionKey)-\(project.persistentModelID)"
        }

        var project: Project {
            switch self {
            case let .clear(project), let .delete(project):
                return project
            }
        }

        var title: String {
            switch self {
            case .clear:
                return "¿Quieres eliminar todas las sesiones de este proyecto?"
            case .delete:
                return "¿Eliminar este proyecto?"
            }
        }

        var message: String {
            switch self {
            case .clear:
                return "Esta acción conserva el proyecto y borra su historial de tiempo."
            case .delete:
                return "Se eliminará el proyecto y su historial asociado."
            }
        }

        var confirmTitle: String {
            switch self {
            case .clear:
                return "Limpiar actividad"
            case .delete:
                return "Eliminar proyecto"
            }
        }

        private var actionKey: String {
            switch self {
            case .clear:
                return "clear"
            case .delete:
                return "delete"
            }
        }
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
                    max: Layout.sidebarMaxWidth,
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
            .sheet(isPresented: $showManualTrackingSheet) {
                ManualTrackingSheetView(
                    projects: projects,
                    onStartExisting: { project in
                        startManualTracking(with: project)
                    },
                    onCreateAndStart: { draft in
                        createManualProjectAndStart(from: draft)
                    },
                )
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .statusItemStartManualTracking)) { _ in
                showManualTrackingSheet = true
            }
        #endif
            .onReceive(tracker.$manualStopEvent.compactMap(\.self)) { event in
                showManualStopToast(event.reason)
            }
            .sheet(isPresented: $showConflictSheet) {
                PendingConflictResolutionView(
                    pendingSessions: pendingSessions,
                    projects: projects,
                )
                .environmentObject(tracker)
            }
            .sheet(isPresented: $showAutomationPrompt) {
                AutomationPermissionPromptView(
                    onOpenSettings: {
                        automationPermissionManager.openSystemSettings()
                        showAutomationPrompt = false
                    },
                    onLater: {
                        showAutomationPrompt = false
                    },
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .onboardingProjectCreated)) { notification in
                handleOnboardingProjectCreated(notification)
            }
            .onChange(of: projects.count) { _, newValue in
                if newValue > 0 {
                    onboardingState.markProjectCreated()
                }
                startPendingOnboardingTrackingIfNeeded()
            }
            .onReceive(tracker.$statusSummary) { summary in
                trackingSessionManager.updateTrackingState(isActive: summary.state == .tracking || summary.state == .trackingManual)
                trackingSessionManager.ingest(summary: summary)
                handleAutomationPromptIfNeeded(for: summary)
            }
            .task {
                showWelcomeWindowIfNeeded()
            }
            .alert(item: $pendingProjectAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text(action.message),
                    primaryButton: .destructive(Text(action.confirmTitle)) {
                        performPendingProjectAction(action)
                    },
                    secondaryButton: .cancel()
                )
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selected = selectedProject {
            ProjectDetailView(
                project: selected,
                isTrackingActiveForProject: isTrackingActiveForSelectedProject,
                onEdit: { activeProjectSheet = .edit($0) },
                onDelete: { deleteProject($0) },
                onClearActivity: { clearActivity(for: $0) },
                onStartTracking: { startTracking(for: $0) },
            )
        } else {
            WelcomeView()
        }
    }

    private var actionPanel: some View {
        ActionPanelView(
            summary: tracker.statusSummary,
            isTrackingEnabled: tracker.isTrackingEnabled,
            isManualTrackingActive: tracker.isManualTrackingActive,
            onToggleTracking: handlePrimaryTrackingAction,
            onStartManualTracking: { showManualTrackingSheet = true },
            onCreateProject: { activeProjectSheet = .create },
            settingsControl: settingsControlView,
        )
        .frame(width: Layout.actionPanelWidth, alignment: .bottomLeading)
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func sidebarChrome(@ViewBuilder content: () -> some View) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: Layout.sidebarCornerRadius, style: .continuous)
                    .fill(.regularMaterial),
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.sidebarCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(Layout.sidebarBorderOpacity), lineWidth: 1),
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
                        .accessibilityIdentifier("dashboard-header")
                }
            }

            Section {
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
                                    pendingProjectAction = .clear(project)
                                }
                                Button("Eliminar", role: .destructive) {
                                    pendingProjectAction = .delete(project)
                                }
                            }
                    }
                    .onDelete(perform: deleteProjects)
                }
            } header: {
                Text("Tus proyectos")
                    .accessibilityIdentifier("projects-section-header")
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
                let shouldAutoStartTracking = onboardingTrackingStarter.shouldAutoStartTracking(
                    hasCreatedProject: onboardingState.hasCreatedProject,
                    existingProjectCount: projects.count,
                )
                let project = Project(
                    name: draft.name,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    assignedApps: draft.assignedApps,
                    assignedDomains: draft.assignedDomains,
                )
                modelContext.insert(project)
                do {
                    try modelContext.save()
                    selectedProjectID = project.persistentModelID
                    if shouldAutoStartTracking {
                        startTracking(for: project)
                    }
                    onboardingState.markProjectCreated()
                    showToast("Proyecto creado", style: .success)
                } catch {
                    showToast("No pudimos crear el proyecto", style: .error)
                }
            }
        case let .edit(project):
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

    private func handlePrimaryTrackingAction() {
        if tracker.isManualTrackingActive {
            tracker.stopManualTracking(reason: .manual)
        } else {
            tracker.toggleTracking()
        }
    }

    private func startManualTracking(with project: Project) {
        tracker.startManualTracking(project: project)
        selectedProjectID = project.persistentModelID
    }

    private func createManualProjectAndStart(from draft: ManualTrackingNewProjectDraft) {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = manualProjectName(from: trimmedName)
        let iconName = draft.icon?.systemName ?? randomManualProjectIcon()
        let project = Project(
            name: projectName,
            colorHex: ProjectPalette.defaultColor.hex,
            iconName: iconName,
        )
        modelContext.insert(project)
        do {
            try modelContext.save()
            startManualTracking(with: project)
            onboardingState.markProjectCreated()
        } catch {
            showToast("No pudimos crear el proyecto", style: .error)
        }
    }

    private func manualProjectName(from baseName: String) -> String {
        let seed = baseName.isEmpty ? "New cool project" : baseName
        let existingNames = Set(projects.map { $0.name.lowercased() })
        let needsSuffix = baseName.isEmpty || existingNames.contains(seed.lowercased())
        guard needsSuffix else { return seed }
        var index = 1
        while true {
            let candidate = "\(seed) (\(index))"
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
    }

    private func randomManualProjectIcon() -> String {
        ProjectIcon.allCases.randomElement()?.systemName ?? ProjectIcon.spark.systemName
    }

    private func clearActivity(for project: Project) {
        let sessions = project.sessions
        for session in sessions {
            modelContext.delete(session)
        }
        do {
            try modelContext.save()
            showToast("Actividad limpiada", style: .success)
        } catch {
            showToast("No pudimos limpiar la actividad", style: .error)
        }
    }

    private func showManualStopToast(_ reason: ActivityTracker.ManualStopReason) {
        let suffix = switch reason {
        case .idle:
            "idle"
        case .manual:
            "manual"
        case .screenLocked:
            "bloqueo"
        }
        showToast("Tracking manual detenido (\(suffix))", style: .success)
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
                    .accessibilityLabel("Ajustes"),
                )
            } else {
                return AnyView(
                    Button(action: openSettingsWindow) {
                        ActionPanelIcon(systemName: "gearshape", tint: .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajustes"),
                )
            }
        #else
            return AnyView(
                Button(action: openSettingsWindow) {
                    ActionPanelIcon(systemName: "gearshape", tint: .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes"),
            )
        #endif
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return projects.first }
        return projects.first(where: { $0.persistentModelID == selectedProjectID })
    }

    private var isTrackingActiveForSelectedProject: Bool {
        guard let selected = selectedProject else { return false }
        let summary = tracker.statusSummary
        let isTrackingState = summary.state == .tracking || summary.state == .trackingManual
        return isTrackingState && summary.projectID == selected.persistentModelID
    }

    private var pendingConflicts: [PendingConflict] {
        PendingConflict.grouped(from: pendingSessions, projects: projects)
    }

    private func startTracking(for project: Project) {
        startManualTracking(with: project)
    }

    private func performPendingProjectAction(_ action: PendingProjectAction) {
        switch action {
        case let .clear(project):
            clearActivity(for: project)
        case let .delete(project):
            deleteProject(project)
        }
    }

    private func handleAutomationPromptIfNeeded(for summary: ActivityTracker.StatusSummary) {
        guard summary.state == .tracking || summary.state == .trackingManual else { return }
        guard !showAutomationPrompt else { return }
        guard let bundleIdentifier = summary.bundleIdentifier else { return }

        if AutomationPermissionManager.browserBundleIdentifiers.contains(bundleIdentifier) {
            guard !onboardingState.hasAutomationPermissionPrompted else { return }
            onboardingState.markAutomationPrompted()
            showAutomationPrompt = true
            return
        }

        if AutomationPermissionManager.documentBundleIdentifiers.contains(bundleIdentifier) {
            guard !onboardingState.hasDocumentAutomationPermissionPrompted else { return }
            onboardingState.markDocumentAutomationPrompted()
            showAutomationPrompt = true
        }
    }

    private func handleOnboardingProjectCreated(_ notification: Notification) {
        guard let identifier = notification.userInfo?[OnboardingUserInfoKey.projectID] as? PersistentIdentifier else {
            return
        }
        selectedProjectID = identifier
        let shouldStartTracking = (notification.userInfo?[OnboardingUserInfoKey.startTracking] as? Bool) ?? false
        if let project = onboardingTrackingStarter.handleNotification(
            projectID: identifier,
            startTracking: shouldStartTracking,
            projects: projects,
        ) {
            startTracking(for: project)
        }
    }

    private func startPendingOnboardingTrackingIfNeeded() {
        guard let project = onboardingTrackingStarter.resolve(projects: projects) else { return }
        startTracking(for: project)
    }

    #if os(macOS)
        private func showWelcomeWindowIfNeeded() {
            guard !onboardingState.hasSeenWelcome, !hasPresentedWelcome else { return }
            hasPresentedWelcome = true
            if #available(macOS 13.0, *) {
                openWindow(id: OnboardingWindowID.welcome)
            }
        }
    #else
        private func showWelcomeWindowIfNeeded() {}
    #endif
}

private enum ProjectSheet: Identifiable {
    case create
    case edit(Project)

    var id: String {
        switch self {
        case .create:
            "create"
        case let .edit(project):
            String(project.persistentModelID.hashValue)
        }
    }
}

private struct ContentViewPreviewWrapper: View {
    let container: ModelContainer
    let tracker: ActivityTracker
    let settings: TrackerSettings
    let catalog: AppCatalog
    let onboardingState: OnboardingState
    let automationPermissionManager: AutomationPermissionManager
    let trackingSessionManager: TrackingSessionManager

    init() {
        guard let schemaContainer = try? ModelContainer(
            for: Project.self,
            TrackingSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true),
        ) else {
            fatalError("Failed to create preview ModelContainer.")
        }
        let previewProject = Project(name: "Certificación UX", colorHex: "#A78BFA", iconName: ProjectIcon.book.systemName)
        previewProject.sessions = [
            TrackingSession(
                startDate: .now.addingTimeInterval(-3600),
                endDate: .now.addingTimeInterval(-1800),
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                domain: nil,
                filePath: nil,
                project: previewProject,
            ),
        ]
        schemaContainer.mainContext.insert(previewProject)

        let previewSettings = TrackerSettings()
        let previewTracker = ActivityTracker(modelContainer: schemaContainer, settings: previewSettings)
        let sampleApps = [
            InstalledApp(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode", url: URL(fileURLWithPath: "/Applications/Xcode.app"), icon: nil),
            InstalledApp(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), icon: nil),
            InstalledApp(bundleIdentifier: "com.apple.Safari", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), icon: nil),
        ]
        let previewCatalog = AppCatalog(searchPaths: [], initialApps: sampleApps)

        container = schemaContainer
        tracker = previewTracker
        settings = previewSettings
        catalog = previewCatalog
        onboardingState = OnboardingState()
        automationPermissionManager = AutomationPermissionManager()
        trackingSessionManager = TrackingSessionManager()
    }

    var body: some View {
        ContentView()
            .environmentObject(tracker)
            .environmentObject(settings)
            .environmentObject(catalog)
            .environmentObject(onboardingState)
            .environmentObject(automationPermissionManager)
            .environmentObject(trackingSessionManager)
            .modelContainer(container)
    }
}

#Preview {
    ContentViewPreviewWrapper()
}
