import SwiftUI
import SwiftData

struct TrackerSettingsView: View {
    @EnvironmentObject private var settings: TrackerSettings
    @EnvironmentObject private var appCatalog: AppCatalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name, order: .forward) private var projects: [Project]

    @State private var draft = TrackerSettingsDraft()
    @State private var showEraseAllConfirmation = false
    @State private var projectPendingDeletion: Project?
    @State private var maintenanceError: String?
    @State private var showingEncryptionInfo = false

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    trackingSection
                    idleSection
                    exclusionSection
                    privacySection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cerrar") { dismiss() }
                    Button("Guardar") {
                        applyChanges()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .navigationTitle("Configuración")
            .frame(minWidth: 360)
        }
        .onAppear {
            draft = TrackerSettingsDraft(from: settings)
        }
        .confirmationDialog("¿Borrar todos los datos?", isPresented: $showEraseAllConfirmation, titleVisibility: .visible) {
            Button("Borrar todo", role: .destructive) { deleteAllData() }
            Button("Cancelar", role: .cancel) { }
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
    }

    private var projectDeletionTitle: String {
        guard let project = projectPendingDeletion else { return "" }
        return "¿Borrar actividad de \(project.name)?"
    }

    private var projectDeletionBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { if !$0 { projectPendingDeletion = nil } }
        )
    }

    private var maintenanceErrorBinding: Binding<Bool> {
        Binding(
            get: { maintenanceError != nil },
            set: { if !$0 { maintenanceError = nil } }
        )
    }

    private var trackingSection: some View {
        Section("Tracking automático") {
            Toggle("Registrar dominios web", isOn: $draft.isDomainTrackingEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Intervalo de detección")
                    Spacer()
                    Text("\(Int(draft.detectionInterval)) s")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $draft.detectionInterval,
                    in: TrackerSettings.minDetectionInterval...TrackerSettings.maxDetectionInterval,
                    step: 1
                )
            }
        }
    }

    private var idleSection: some View {
        Section("Inactividad") {
            VStack(alignment: .leading, spacing: 8) {
                Stepper(
                    value: $draft.idleThresholdMinutes,
                    in: TrackerSettings.minIdleMinutes...TrackerSettings.maxIdleMinutes
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

    private var exclusionSection: some View {
        Section("Exclusiones globales") {
            AppExclusionEditor(excludedApps: $draft.excludedApps)

            ExclusionListEditor(
                title: "Dominios",
                subtitle: "Se compara contra el dominio detectado. Puedes usar fragmentos como youtube.com.",
                placeholder: "dominio.com",
                lowercaseStorage: true,
                items: $draft.excludedDomains
            )
        }
    }

    private var privacySection: some View {
        Section("Privacidad y datos") {
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

    @MainActor
    private func applyChanges() {
        settings.isDomainTrackingEnabled = draft.isDomainTrackingEnabled
        settings.detectionInterval = draft.detectionInterval
        settings.idleThresholdMinutes = draft.idleThresholdMinutes
        settings.excludedApps = draft.excludedApps
        settings.excludedDomains = draft.excludedDomains
        settings.isDatabaseEncryptionEnabled = draft.isDatabaseEncryptionEnabled
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

@MainActor
private struct TrackerSettingsDraft {
    var detectionInterval: Double
    var idleThresholdMinutes: Int
    var isDomainTrackingEnabled: Bool
    var excludedApps: [String]
    var excludedDomains: [String]
    var isDatabaseEncryptionEnabled: Bool

    init(from settings: TrackerSettings) {
        detectionInterval = settings.detectionInterval
        idleThresholdMinutes = settings.idleThresholdMinutes
        isDomainTrackingEnabled = settings.isDomainTrackingEnabled
        excludedApps = settings.excludedApps
        excludedDomains = settings.excludedDomains
        isDatabaseEncryptionEnabled = settings.isDatabaseEncryptionEnabled
    }

    init() {
        detectionInterval = TrackerSettings.minDetectionInterval
        idleThresholdMinutes = 15
        isDomainTrackingEnabled = true
        excludedApps = []
        excludedDomains = []
        isDatabaseEncryptionEnabled = false
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

            if resolvedApps.isEmpty && unresolvedIDs.isEmpty {
                Text("No hay apps excluidas. Usa el botón para añadir desde el catálogo o escribe el bundle ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !resolvedApps.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                        ForEach(resolvedApps, id: \.bundleIdentifier) { app in
                            ExcludedAppChip(title: app.name, subtitle: app.bundleIdentifier, icon: app.icon) {
                                remove(identifier: app.bundleIdentifier)
                            }
                        }
                    }
                }

                if !unresolvedIDs.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                        ForEach(unresolvedIDs, id: \.self) { identifier in
                            ExcludedAppChip(title: identifier, subtitle: nil, icon: Image(systemName: "app")) {
                                remove(identifier: identifier)
                            }
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
                    arrowEdge: .top
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
                    TextField("com.ejemplo.app", text: $manualEntry)
                        .textFieldStyle(.roundedBorder)
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

            TextField("Buscar apps", text: $searchText)
                .textFieldStyle(.roundedBorder)

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
                                isSelected: contains(identifier: app.bundleIdentifier)
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
    let subtitle: String?
    let icon: Image
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            icon
                .resizable()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                TextField(placeholder, text: $newEntry)
                    .textFieldStyle(.roundedBorder)
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

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
