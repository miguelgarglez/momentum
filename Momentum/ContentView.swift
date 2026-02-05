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
    @State private var projectStatsCache: [PersistentIdentifier: ProjectRowView.ProjectRowStats] = [:]
    @State private var dashboardMetrics = DashboardMetricsDisplay.loading
    @State private var lastStatsRefreshDate: Date?
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        @State private var shouldSuppressInitialWindow = true
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
        static let windowMinHeight: CGFloat = ActionPanelView.minimumHeight + sidebarInset * 2 + 125
    }

    private static let diagnosticsUIEnabled = ProcessInfo.processInfo.environment["MOM_DIAG_UI"] == "1"
    private static let diagnosticsUIInterval: TimeInterval = {
        let raw = ProcessInfo.processInfo.environment["MOM_DIAG_UI_INTERVAL_S"] ?? ""
        if let value = Double(raw), value > 0 {
            return value
        }
        return 6
    }()

    private enum PendingProjectAction: Identifiable {
        case clear(Project)
        case delete(Project)

        var id: String {
            "\(actionKey)-\(project.persistentModelID)"
        }

        var project: Project {
            switch self {
            case let .clear(project), let .delete(project):
                project
            }
        }

        var title: String {
            switch self {
            case .clear:
                "¿Quieres eliminar todas las sesiones de este proyecto?"
            case .delete:
                "¿Eliminar este proyecto?"
            }
        }

        var message: String {
            switch self {
            case .clear:
                "Esta acción conserva el proyecto y borra su historial de tiempo."
            case .delete:
                "Se eliminará el proyecto y su historial asociado."
            }
        }

        var confirmTitle: String {
            switch self {
            case .clear:
                "Limpiar actividad"
            case .delete:
                "Eliminar proyecto"
            }
        }

        private var actionKey: String {
            switch self {
            case .clear:
                "clear"
            case .delete:
                "delete"
            }
        }
    }

    private enum StatsRefreshPolicy {
        static let refreshInterval: TimeInterval = 600
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: Layout.actionPanelWidth)
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
                actionPanelOverlay
            }

            if let toast {
                ToastView(message: toast.message, style: toast.style)
                    .padding(.bottom, 24)
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
            .animation(Layout.toastAnimation, value: toast)
            .frame(minHeight: Layout.windowMinHeight)
        #if os(macOS)
            .background(
                MainWindowVisibilityObserver(
                    shouldSuppressInitialWindow: $shouldSuppressInitialWindow,
                ),
            )
            .background(
                WindowCloseAccessoryHandler(),
            )
            .onReceive(NotificationCenter.default.publisher(for: .statusItemShowApp)) { _ in
                showMainWindowFromStatusItem()
            }
            .onReceive(NotificationCenter.default.publisher(for: .statusItemOpenProject)) { notification in
                guard let identifier = notification.userInfo?[StatusItemUserInfoKey.projectID] as? PersistentIdentifier else { return }
                selectedProjectID = identifier
            }
            .onReceive(NotificationCenter.default.publisher(for: .statusItemStartManualTracking)) { _ in
                showManualTrackingSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .raycastShowConflicts)) { _ in
                showMainWindowFromStatusItem()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showConflictSheet = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .statusItemShowSettings)) { _ in
                MomentumDeepLink.openSettings(section: nil)
            }
        #endif
            .onReceive(tracker.$manualStopEvent.compactMap(\.self)) { event in
                showManualStopToast(event.reason)
            }
            .task(id: Self.diagnosticsUIEnabled) {
                guard Self.diagnosticsUIEnabled else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(Self.diagnosticsUIInterval * 1_000_000_000))
                    cycleDiagnosticsSelection()
                }
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
            .onChange(of: projects.map(\.persistentModelID)) { _, _ in
                Task { await refreshProjectStatsIfNeeded(force: true) }
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
            .task {
                await refreshProjectStatsIfNeeded(force: true)
                await refreshProjectStatsLoop()
            }
            .alert(item: $pendingProjectAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text(action.message),
                    primaryButton: .destructive(Text(action.confirmTitle)) {
                        performPendingProjectAction(action)
                    },
                    secondaryButton: .cancel(),
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
            statusAccessory: pendingConflicts.isEmpty
                ? nil
                : AnyView(
                    PendingConflictCompactIndicator(count: pendingConflicts.count) {
                        showConflictSheet = true
                    }
                ),
        )
        .frame(width: Layout.actionPanelWidth, alignment: .bottomLeading)
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
        .zIndex(2)
    }

    private var actionPanelOverlay: some View {
        actionPanel
            .background {
                if columnVisibility == .detailOnly {
                    RoundedRectangle(cornerRadius: Layout.sidebarCornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.sidebarCornerRadius, style: .continuous)
                                .stroke(Color.primary.opacity(Layout.sidebarBorderOpacity), lineWidth: 1)
                        )
                        .padding(.leading, Layout.sidebarInset)
                        // Negative trailing padding aligns the chrome edge with the window border in collapsed mode.
                        // This offsets the extra material inset introduced by the split view + overlay composition.
                        .padding(.trailing, -4)
                        .padding(.vertical, Layout.sidebarInset)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
    }

    private var sidebarList: some View {
        List(selection: $selectedProjectID) {
            if !projects.isEmpty {
                Section {
                    DashboardHeaderView(metrics: dashboardMetrics)
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
                        ProjectRowView(project: project, stats: projectStatsCache[project.persistentModelID])
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

    @MainActor
    private func refreshProjectStatsIfNeeded(force: Bool) async {
        let now = Date()
        if let lastStatsRefreshDate, !force {
            let elapsed = now.timeIntervalSince(lastStatsRefreshDate)
            if elapsed < StatsRefreshPolicy.refreshInterval {
                return
            }
        }

        var cache: [PersistentIdentifier: ProjectRowView.ProjectRowStats] = [:]
        var totals = (total: TimeInterval(0), monthly: TimeInterval(0), weekly: TimeInterval(0), daily: TimeInterval(0))
        for project in projects {
            let totalSeconds = project.totalSeconds
            let weeklySeconds = project.weeklySeconds
            let dailySeconds = project.dailySeconds
            let monthlySeconds = project.monthlySeconds
            cache[project.persistentModelID] = ProjectRowView.ProjectRowStats(
                totalSeconds: totalSeconds,
                dailySeconds: dailySeconds,
                weeklySeconds: weeklySeconds,
            )
            totals.total += totalSeconds
            totals.monthly += monthlySeconds
            totals.weekly += weeklySeconds
            totals.daily += dailySeconds
        }

        projectStatsCache = cache
        dashboardMetrics = DashboardMetricsDisplay(
            total: totals.total.hoursAndMinutesString,
            monthly: totals.monthly.hoursAndMinutesString,
            weekly: totals.weekly.hoursAndMinutesString,
            daily: totals.daily.hoursAndMinutesString,
        )
        lastStatsRefreshDate = now
    }

    private func refreshProjectStatsLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(StatsRefreshPolicy.refreshInterval))
            } catch {
                return
            }
            await refreshProjectStatsIfNeeded(force: false)
        }
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
                    assignedFiles: draft.assignedFiles,
                )
                let contexts = AssignmentRuleInvalidator.contextsForNewProject(
                    apps: draft.assignedApps,
                    domains: draft.assignedDomains,
                    files: draft.assignedFiles,
                )
                modelContext.insert(project)
                AssignmentRuleInvalidator(modelContext: modelContext)
                    .invalidateRules(for: contexts)
                do {
                    try modelContext.save()
                    tracker.refreshPendingConflicts()
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
                let contexts = AssignmentRuleInvalidator.contextsForUpdatedProject(
                    apps: draft.assignedApps,
                    domains: draft.assignedDomains,
                    files: draft.assignedFiles,
                    previousApps: project.assignedApps,
                    previousDomains: project.assignedDomains,
                    previousFiles: project.assignedFiles,
                )
                let removedContexts = AssignmentRuleInvalidator.contextsForRemovedProject(
                    apps: draft.assignedApps,
                    domains: draft.assignedDomains,
                    files: draft.assignedFiles,
                    previousApps: project.assignedApps,
                    previousDomains: project.assignedDomains,
                    previousFiles: project.assignedFiles,
                )
                project.apply(draft: draft)
                AssignmentRuleInvalidator(modelContext: modelContext)
                    .invalidateRules(for: contexts)
                AssignmentRuleInvalidator(modelContext: modelContext)
                    .invalidateRules(for: removedContexts, createPendingConflicts: false)
                do {
                    try modelContext.save()
                    tracker.refreshPendingConflicts()
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

    private func cycleDiagnosticsSelection() {
        guard !projects.isEmpty else { return }
        let currentIndex = projects.firstIndex { $0.persistentModelID == selectedProjectID } ?? -1
        let nextIndex = (currentIndex + 1) % projects.count
        selectedProjectID = projects[nextIndex].persistentModelID
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
        let iconName = draft.iconName ?? randomManualProjectIcon()
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
        project.markStatsDirty()
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
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.unhide(nil)
                openWindow(id: OnboardingWindowID.welcome)
                NotificationCenter.default.post(name: .momentumWindowVisibilityNeedsUpdate, object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    bringWelcomeWindowToFrontIfNeeded()
                }
            }
        }

        private func showMainWindowFromStatusItem() {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.unhide(nil)
            NSApp.setActivationPolicy(.regular)
            if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }

        private func showSettingsFromStatusItem() {
            SettingsWindowPresenter.open(section: nil)
        }

        private func bringWelcomeWindowToFrontIfNeeded() {
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else { return }
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
            window.orderFrontRegardless()
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

#if os(macOS)
    private final class WindowAttachmentView: NSView {
        var onWindowChange: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowChange?(window)
            }
        }
    }

    private struct MainWindowVisibilityObserver: NSViewRepresentable {
        @Binding var shouldSuppressInitialWindow: Bool

        func makeNSView(context: Context) -> WindowAttachmentView {
            let view = WindowAttachmentView()
            view.onWindowChange = { window in
                context.coordinator.handle(window: window, shouldSuppressInitialWindow: $shouldSuppressInitialWindow)
            }
            return view
        }

        func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
            nsView.onWindowChange = { window in
                context.coordinator.handle(window: window, shouldSuppressInitialWindow: $shouldSuppressInitialWindow)
            }
            if let window = nsView.window {
                context.coordinator.handle(window: window, shouldSuppressInitialWindow: $shouldSuppressInitialWindow)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        final class Coordinator {
            private weak var lastWindow: NSWindow?

            func handle(window: NSWindow, shouldSuppressInitialWindow: Binding<Bool>) {
                guard lastWindow !== window else { return }
                lastWindow = window
                if MainWindowSuppression.consume() {
                    window.orderOut(nil)
                    return
                }
                if shouldSuppressInitialWindow.wrappedValue {
                    shouldSuppressInitialWindow.wrappedValue = false
                    window.orderOut(nil)
                    return
                }
                if window.isVisible {
                    NotificationCenter.default.post(name: .momentumWindowVisibilityNeedsUpdate, object: nil)
                }
            }
        }
    }
#endif

private struct ContentViewPreviewWrapper: View {
    let container: ModelContainer
    let tracker: ActivityTracker
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
        catalog = previewCatalog
        onboardingState = OnboardingState()
        automationPermissionManager = AutomationPermissionManager()
        trackingSessionManager = TrackingSessionManager()
    }

    var body: some View {
        ContentView()
            .environmentObject(tracker)
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
