import Foundation
import SwiftData
import SwiftUI

@MainActor
struct TrackerSettingsView: View {
    @EnvironmentObject private var settings: TrackerSettings
    @EnvironmentObject private var appCatalog: AppCatalog
    @EnvironmentObject private var themePreview: ThemePreviewState
    @EnvironmentObject private var automationPermissionManager: AutomationPermissionManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name, order: .forward) private var projects: [Project]

    @Binding var draft: TrackerSettingsDraft
    let section: SettingsSection?
    @State private var showEraseAllConfirmation = false
    @State private var projectPendingDeletion: Project?
    @State private var maintenanceError: String?
    @State private var showingEncryptionInfo = false
    @State private var showingAutomationInfo = false

    init(draft: Binding<TrackerSettingsDraft>, section: SettingsSection? = nil) {
        _draft = draft
        self.section = section
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let section {
                    sectionView(for: section)
                } else {
                    ForEach(SettingsSection.allCases) { section in
                        sectionView(for: section)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Configuración")
        .frame(minWidth: 360)
        .confirmationDialog("¿Borrar todos los datos?", isPresented: $showEraseAllConfirmation, titleVisibility: .visible) {
            Button("Borrar todo", role: .destructive) { deleteAllData() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acción reinicia Momentum y elimina proyectos, sesiones y resúmenes. No se puede deshacer.")
        }
        .confirmationDialog(projectDeletionTitle, isPresented: projectDeletionBinding, titleVisibility: .visible) {
            Button("Borrar actividad", role: .destructive) {
                if let project = projectPendingDeletion {
                    deleteActivity(for: project)
                }
                projectPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) { projectPendingDeletion = nil }
        } message: {
            if let project = projectPendingDeletion {
                Text("Se eliminarán las sesiones y resúmenes asociados a \(project.name). El proyecto permanecerá intacto.")
            }
        }
        .alert("No se pudo completar la operación", isPresented: maintenanceErrorBinding) {
            Button("Aceptar", role: .cancel) { maintenanceError = nil }
        } message: {
            Text(maintenanceError ?? "")
        }
        .alert("Cifrado de base de datos", isPresented: $showingEncryptionInfo) {
            Button("Entendido", role: .cancel) { showingEncryptionInfo = false }
        } message: {
            Text("Al activar esta opción, macOS aplica FileProtection al archivo de Momentum. Los datos solo se pueden leer cuando tu sesión está desbloqueada; si alguien copia el fichero sin permiso verá información cifrada. Puedes dejarlo desactivado si ya confías en FileVault o si compartes la base con otras herramientas.")
        }
        #if os(macOS)
        .sheet(isPresented: $showingAutomationInfo) {
            AutomationPermissionPromptView(
                onOpenSettings: automationPermissionManager.openSystemSettings,
                onLater: { showingAutomationInfo = false },
            )
        }
        #endif
    }

    private var projectDeletionTitle: String {
        guard let project = projectPendingDeletion else { return "" }
        return "¿Borrar actividad de \(project.name)?"
    }

    private var projectDeletionBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { if !$0 { projectPendingDeletion = nil } },
        )
    }

    private var maintenanceErrorBinding: Binding<Bool> {
        Binding(
            get: { maintenanceError != nil },
            set: { if !$0 { maintenanceError = nil } },
        )
    }

    private var themeSelectionBinding: Binding<AppThemePreference> {
        Binding(
            get: { themePreview.selection ?? settings.themePreference },
            set: { themePreview.selection = $0 },
        )
    }

    @ViewBuilder
    private func sectionView(for section: SettingsSection) -> some View {
        switch section {
        case .tracking:
            SettingsTrackingSectionView(
                draft: $draft,
                showingAutomationInfo: $showingAutomationInfo,
            )
        case .appearance:
            SettingsAppearanceSectionView(themeSelection: themeSelectionBinding)
        case .idle:
            SettingsIdleSectionView(draft: $draft)
        case .exclusions:
            SettingsExclusionSectionView(draft: $draft)
        case .assignmentRules:
            SettingsAssignmentRulesSectionView(draft: $draft)
        case .privacy:
            SettingsPrivacySectionView(
                draft: $draft,
                projects: projects,
                showEraseAllConfirmation: $showEraseAllConfirmation,
                showingEncryptionInfo: $showingEncryptionInfo,
                projectPendingDeletion: $projectPendingDeletion,
            )
        }
    }

    @MainActor
    private func deleteAllData() {
        do {
            if #available(macOS 15, iOS 18, *) {
                try modelContext.container.erase()
            } else {
                modelContext.container.deleteAllData()
            }
            try? modelContext.save()
        } catch {
            maintenanceError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteActivity(for project: Project) {
        do {
            project.sessions.forEach { modelContext.delete($0) }
            project.dailySummaries.forEach { modelContext.delete($0) }

            try modelContext.save()
        } catch {
            maintenanceError = error.localizedDescription
        }
    }
}

#if os(macOS)
    struct WindowCloseObserver: NSViewRepresentable {
        let onClose: @Sendable () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onClose: onClose)
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async {
                context.coordinator.attach(to: view.window)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async {
                context.coordinator.attach(to: nsView.window)
            }
        }

        final class Coordinator {
            private let onClose: @Sendable () -> Void
            private weak var window: NSWindow?
            private var observer: NSObjectProtocol?

            init(onClose: @escaping @Sendable () -> Void) {
                self.onClose = onClose
            }

            func attach(to window: NSWindow?) {
                guard self.window !== window else { return }
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                self.window = window
                guard let window else { return }
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main,
                ) { [onClose] _ in
                    onClose()
                }
            }

        }
    }
#endif

@MainActor
struct TrackerSettingsDraft {
    var detectionInterval: Double
    var idleThresholdMinutes: Int
    var isDomainTrackingEnabled: Bool
    var isFileTrackingEnabled: Bool
    var excludedApps: [String]
    var excludedDomains: [String]
    var excludedFiles: [String]
    var isDatabaseEncryptionEnabled: Bool
    var assignmentRuleExpiration: AssignmentRuleExpirationOption

    init(from settings: TrackerSettings) {
        detectionInterval = settings.detectionInterval
        idleThresholdMinutes = settings.idleThresholdMinutes
        isDomainTrackingEnabled = settings.isDomainTrackingEnabled
        isFileTrackingEnabled = settings.isFileTrackingEnabled
        excludedApps = settings.excludedApps
        excludedDomains = settings.excludedDomains
        excludedFiles = settings.excludedFiles
        isDatabaseEncryptionEnabled = settings.isDatabaseEncryptionEnabled
        assignmentRuleExpiration = settings.assignmentRuleExpiration
    }

    init() {
        detectionInterval = TrackerSettings.minDetectionInterval
        idleThresholdMinutes = 15
        isDomainTrackingEnabled = true
        isFileTrackingEnabled = true
        excludedApps = []
        excludedDomains = []
        excludedFiles = []
        isDatabaseEncryptionEnabled = false
        assignmentRuleExpiration = .never
    }
}
