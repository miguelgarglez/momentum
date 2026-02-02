import Foundation
import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct SettingsExclusionSectionView: View {
    @Binding var draft: TrackerSettingsDraft

    var body: some View {
        Section {
            if draft.excludedApps.isEmpty,
               draft.excludedDomains.isEmpty,
               draft.excludedFiles.isEmpty
            {
                Text("Sin exclusiones configuradas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            AppExclusionEditor(excludedApps: $draft.excludedApps)

            ExclusionListEditor(
                title: "Dominios",
                subtitle: "Se compara contra el dominio detectado. Puedes usar fragmentos como youtube.com.",
                placeholder: "dominio.com",
                lowercaseStorage: true,
                items: $draft.excludedDomains,
            )

            FileExclusionEditor(items: $draft.excludedFiles)
        } header: {
            SettingsSectionHeader(
                "Exclusiones",
                subtitle: "Evita registrar apps, dominios o archivos que no quieras trackear.",
            )
        }
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
            .onChange(of: isSelectorPresented) { _, isPresented in
                if isPresented {
                    appCatalog.refreshIfStale()
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
