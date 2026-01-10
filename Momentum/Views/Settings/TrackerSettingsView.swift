import Foundation
import SwiftData
import SwiftUI
#if os(macOS)
    import AppKit
#endif

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

private struct SettingsAppearanceSectionView: View {
    @Binding var themeSelection: AppThemePreference
    @EnvironmentObject private var themePreview: ThemePreviewState

    var body: some View {
        Section("Apariencia") {
            Text("Ajusta el tema visual que verás en toda la app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Tema", selection: $themeSelection) {
                ForEach(AppThemePreference.allCases) { option in
                    Text(option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .transaction { $0.disablesAnimations = true }
            .animation(.none, value: themePreview.selection)
        }
    }
}

private struct SettingsTrackingSectionView: View {
    @Binding var draft: TrackerSettingsDraft
    @Binding var showingAutomationInfo: Bool

    #if os(macOS)
        @EnvironmentObject private var automationPermissionManager: AutomationPermissionManager
    #endif

    var body: some View {
        Section("Tracking automático") {
            Text("Controla qué fuentes registra Momentum y la frecuencia de detección.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Registrar dominios web", isOn: $draft.isDomainTrackingEnabled)
            Toggle("Registrar archivos", isOn: $draft.isFileTrackingEnabled)

            #if os(macOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Momentum solo solicita permisos de Automatización cuando necesita rastrear apps donde detecta archivos o dominios. Si los deniegas, puedes reactivarlos desde Ajustes del sistema.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Abrir ajustes de Automatización") {
                            automationPermissionManager.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                        Button("Más info") {
                            showingAutomationInfo = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("automation-permission-info")
                    }
                }
            #endif

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Intervalo de detección")
                    Spacer()
                    Text("\(Int(draft.detectionInterval)) s")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $draft.detectionInterval,
                    in: TrackerSettings.minDetectionInterval ... TrackerSettings.maxDetectionInterval,
                    step: 1,
                )
            }
        }
    }
}

private struct SettingsIdleSectionView: View {
    @Binding var draft: TrackerSettingsDraft

    var body: some View {
        Section("Inactividad") {
            Text("Define cuándo considerar una sesión inactiva y pausar el registro.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Stepper(
                    value: $draft.idleThresholdMinutes,
                    in: TrackerSettings.minIdleMinutes ... TrackerSettings.maxIdleMinutes,
                ) {
                    HStack {
                        Text("Umbral de inactividad")
                        Spacer()
                        Text("\(draft.idleThresholdMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Momentum pausará el tracking tras este tiempo sin interacción.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsExclusionSectionView: View {
    @Binding var draft: TrackerSettingsDraft

    var body: some View {
        Section("Exclusiones globales") {
            Text("Evita registrar apps, dominios o archivos que no quieras trackear.")
                .font(.caption)
                .foregroundStyle(.secondary)
            AppExclusionEditor(excludedApps: $draft.excludedApps)

            ExclusionListEditor(
                title: "Dominios",
                subtitle: "Se compara contra el dominio detectado. Puedes usar fragmentos como youtube.com.",
                placeholder: "dominio.com",
                lowercaseStorage: true,
                items: $draft.excludedDomains,
            )

            FileExclusionEditor(items: $draft.excludedFiles)
        }
    }
}

private struct SettingsAssignmentRulesSectionView: View {
    @Binding var draft: TrackerSettingsDraft

    var body: some View {
        Section("Reglas de asignacion") {
            Text("Configura cómo se asignan automáticamente las sesiones a proyectos.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Expiración de reglas", selection: $draft.assignmentRuleExpiration) {
                ForEach(AssignmentRuleExpirationOption.allCases) { option in
                    Text(option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("assignment-rules-expiration-picker")

            NavigationLink("Gestionar reglas de asignacion") {
                AssignmentRulesView()
            }
            .accessibilityIdentifier("assignment-rules-link")

            Text("Las reglas expiradas se eliminan automáticamente, y podrás reinstalarlas al resolver un conflicto.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsPrivacySectionView: View {
    @Binding var draft: TrackerSettingsDraft
    let projects: [Project]
    @Binding var showEraseAllConfirmation: Bool
    @Binding var showingEncryptionInfo: Bool
    @Binding var projectPendingDeletion: Project?

    var body: some View {
        Section("Privacidad y datos") {
            Text("Gestiona la protección de tu base de datos y limpieza de actividad.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(isOn: $draft.isDatabaseEncryptionEnabled) {
                HStack(spacing: 6) {
                    Text("Cifrar base de datos")
                    Button {
                        showingEncryptionInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Más información")
                }
            }

            Button(role: .destructive) {
                showEraseAllConfirmation = true
            } label: {
                Label("Borrar todos los datos", systemImage: "trash")
            }

            if projects.isEmpty {
                Text("No hay proyectos para limpiar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(projects) { project in
                        Button(role: .destructive) {
                            projectPendingDeletion = project
                        } label: {
                            Text(project.name)
                        }
                    }
                } label: {
                    Label("Borrar actividad de un proyecto", systemImage: "folder.badge.minus")
                }
            }
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

private struct AppExclusionEditor: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    @Binding var excludedApps: [String]
    @State private var manualEntry: String = ""
    @State private var isSelectorPresented = false

    private var resolvedApps: [InstalledApp] {
        excludedApps
            .compactMap { appCatalog.app(for: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unresolvedIDs: [String] {
        excludedApps
            .filter { appCatalog.app(for: $0) == nil }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps")
                .font(.headline)

            if resolvedApps.isEmpty, unresolvedIDs.isEmpty {
                Text("No hay apps excluidas. Usa el botón para añadir desde el catálogo o escribe el bundle ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(resolvedApps, id: \.bundleIdentifier) { app in
                        ExcludedAppChip(title: app.name, icon: app.icon) {
                            remove(identifier: app.bundleIdentifier)
                        }
                    }
                    ForEach(unresolvedIDs, id: \.self) { identifier in
                        ExcludedAppChip(title: identifier, icon: Image(systemName: "app")) {
                            remove(identifier: identifier)
                        }
                    }
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
                    arrowEdge: .top,
                ) {
                    AppCatalogSelectionPanel(excludedApps: $excludedApps)
                        .frame(width: 360, height: 420)
                        .padding()
                }
                .contextMenu {
                    if appCatalog.apps.isEmpty {
                        Text("Catálogo vacío")
                    } else {
                        ForEach(appCatalog.apps.prefix(8)) { app in
                            Button(app.name) {
                                add(identifier: app.bundleIdentifier)
                            }
                        }
                        if appCatalog.apps.count > 8 {
                            Divider()
                            Text("Usa el selector para ver todas las apps")
                                .font(.caption)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Bundle ID manual")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack {
                    #if os(macOS)
                        LTRTextField(
                            text: $manualEntry,
                            placeholder: "com.ejemplo.app",
                        )
                        .macRoundedTextFieldStyle()
                    #else
                        TextField("com.ejemplo.app", text: $manualEntry)
                            .textFieldStyle(.roundedBorder)
                    #endif
                    Button("Añadir") {
                        add(identifier: manualEntry)
                        manualEntry = ""
                    }
                    .disabled(manualEntry.trimmed().isEmpty)
                }
            }
        }
    }

    private func add(identifier: String) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !contains(identifier: trimmed) else { return }
        excludedApps.append(trimmed)
        excludedApps.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func remove(identifier: String) {
        excludedApps.removeAll { $0.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    private func contains(identifier: String) -> Bool {
        excludedApps.contains { $0.caseInsensitiveCompare(identifier) == .orderedSame }
    }
}

private struct AppCatalogSelectionPanel: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    @Binding var excludedApps: [String]
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
            Text("Selecciona apps a excluir")
                .font(.headline)

            #if os(macOS)
                LTRTextField(
                    text: $searchText,
                    placeholder: "Buscar apps",
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
                                isSelected: contains(identifier: app.bundleIdentifier),
                            ) {
                                toggle(identifier: app.bundleIdentifier)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Text("Haz clic para alternar la exclusión. Puedes cerrar el panel cuando termines.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(identifier: String) {
        if contains(identifier: identifier) {
            excludedApps.removeAll { $0.caseInsensitiveCompare(identifier) == .orderedSame }
        } else {
            excludedApps.append(identifier)
            excludedApps.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    private func contains(identifier: String) -> Bool {
        excludedApps.contains { $0.caseInsensitiveCompare(identifier) == .orderedSame }
    }
}

private struct ExcludedAppChip: View {
    let title: String
    let icon: Image
    let onRemove: () -> Void

    var body: some View {
        RemovableChip(
            title: title,
            removeAccessibilityLabel: "Eliminar app excluida",
            leading: {
                icon
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            },
            onRemove: onRemove,
        )
    }
}

private struct ExclusionListEditor: View {
    let title: String
    let subtitle: String
    let placeholder: String
    var lowercaseStorage = false
    @Binding var items: [String]
    @State private var newEntry: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if items.isEmpty {
                Text("No hay elementos excluidos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        HStack {
                            Text(item)
                                .font(.subheadline)
                            Spacer()
                            Button {
                                remove(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Eliminar \(item)")
                        }
                        .padding(8)
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack {
                #if os(macOS)
                    LTRTextField(
                        text: $newEntry,
                        placeholder: placeholder,
                    )
                    .macRoundedTextFieldStyle()
                #else
                    TextField(placeholder, text: $newEntry)
                        .textFieldStyle(.roundedBorder)
                #endif
                Button("Añadir") { addEntry() }
                    .disabled(newEntry.trimmed().isEmpty)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addEntry() {
        let trimmed = newEntry.trimmed()
        guard !trimmed.isEmpty else { return }
        let normalized = lowercaseStorage ? trimmed.lowercased() : trimmed
        let exists = items.contains { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        guard !exists else {
            newEntry = ""
            return
        }
        items.append(normalized)
        newEntry = ""
    }

    private func remove(_ item: String) {
        if let index = items.firstIndex(of: item) {
            items.remove(at: index)
        }
    }
}

private struct FileExclusionEditor: View {
    @Binding var items: [String]
    @State private var newEntry: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Archivos")
                    .font(.headline)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if items.isEmpty {
                Text("No hay archivos excluidos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        HStack {
                            Text(item)
                                .font(.subheadline)
                            Spacer()
                            Button {
                                remove(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Eliminar \(item)")
                        }
                        .padding(8)
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack {
                #if os(macOS)
                    LTRTextField(
                        text: $newEntry,
                        placeholder: "Ruta o terminación (ej: /Users/... o .key)",
                    )
                    .macRoundedTextFieldStyle()
                #else
                    TextField("Ruta o terminación (ej: /Users/... o .key)", text: $newEntry)
                        .textFieldStyle(.roundedBorder)
                #endif
                Button("Añadir") { addEntry() }
                    .disabled(newEntry.trimmed().isEmpty)
            }

            #if os(macOS)
                HStack {
                    Spacer()
                    Button("Seleccionar archivos…") {
                        selectFiles()
                    }
                }
            #endif

            Text("Puedes excluir rutas exactas o terminaciones como *.key, .pdf o .mov.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addEntry() {
        let trimmed = newEntry.trimmed()
        guard !trimmed.isEmpty else { return }
        addItems([trimmed])
        newEntry = ""
    }

    private func remove(_ item: String) {
        if let index = items.firstIndex(of: item) {
            items.remove(at: index)
        }
    }

    private func addItems(_ entries: [String]) {
        for entry in entries {
            let trimmed = entry.trimmed()
            guard !trimmed.isEmpty else { continue }
            let isPath = trimmed.contains("/") || trimmed.hasPrefix("~")
            let expanded = trimmed.hasPrefix("~") ? (trimmed as NSString).expandingTildeInPath : trimmed
            let normalized = isPath ? expanded.normalizedFilePath : ""
            let value = normalized.isEmpty ? trimmed : normalized
            let exists = items.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            guard !exists else { continue }
            items.append(value)
        }
    }

    #if os(macOS)
        private func selectFiles() {
            let panel = NSOpenPanel()
            panel.title = "Selecciona archivos para excluir"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = true
            panel.begin { response in
                guard response == .OK else { return }
                let paths = panel.urls.map(\.path)
                addItems(paths)
            }
        }
    #endif
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
