//
//  ProjectFormView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appCatalog: AppCatalog
    @State private var draft: ProjectFormDraft
    private let mode: FormMode

    let onSave: (ProjectFormDraft) -> Void

    init(project: Project? = nil, onSave: @escaping (ProjectFormDraft) -> Void) {
        self.onSave = onSave
        mode = project == nil ? .create : .edit
        _draft = State(initialValue: ProjectFormDraft(project: project))
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
                    ColorPicker(
                        "Selector",
                        selection: Binding(
                            get: { Color(hex: draft.colorHex) ?? .accentColor },
                            set: { newValue in
                                guard let hex = newValue.hexString() else { return }
                                draft.colorHex = hex
                            }
                        ),
                        supportsOpacity: false
                    )

                    colorSwatchSection(title: "Predeterminados", colors: ProjectPalette.colors.map(\.hex))
                }

                AppAutoTrackingSection(
                    selection: $draft.selectedAppIDs,
                    manualApps: $draft.manualApps,
                )

                Section("Dominios") {
                    #if os(macOS)
                        LTRTextField(
                            text: $draft.domains,
                            placeholder: "Dominios (separados por coma)",
                            accessibilityIdentifier: "project-domains-field",
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

                Section("Archivos") {
                    #if os(macOS)
                        if !draft.assignedFiles.isEmpty {
                            FileSelectionChips(
                                filePaths: draft.assignedFiles,
                                onRemove: { path in
                                    draft.removeFile(path)
                                },
                            )
                        }

                        Button("Seleccionar archivos…") {
                            selectFiles()
                        }
                        .buttonStyle(.bordered)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Añadir rutas manualmente")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                            HStack {
                                LTRTextField(
                                    text: $draft.manualFilesEntry,
                                    placeholder: "Rutas de archivo (separadas por coma)",
                                    accessibilityIdentifier: "project-files-field",
                                )
                                .macRoundedTextFieldStyle()
                                Button("Añadir") {
                                    draft.addManualFilesEntry()
                                }
                                .disabled(draft.manualFilesEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    #else
                        TextField("Rutas de archivo (separadas por coma)", text: $draft.manualFilesEntry)
                            .accessibilityIdentifier("project-files-field")
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 4)
                    #endif
                    Text("Guardamos la ruta del archivo para reconocerlo en el tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
#if os(macOS)
                        NSColorPanel.shared.close()
#endif
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? "Crear" : "Guardar") {
                        onSave(draft)
#if os(macOS)
                        NSColorPanel.shared.close()
#endif
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func colorSwatchSection(title: String, colors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .accentColor)
                            .frame(width: 44, height: 44)
                            .overlay {
                                if hex == draft.colorHex {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            .onTapGesture {
                                draft.colorHex = hex
                            }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private enum FormMode {
        case create
        case edit
    }
}

#if os(macOS)
    private extension ProjectFormView {
        @MainActor
        func selectFiles() {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false
            panel.prompt = "Seleccionar"
            panel.begin { response in
                guard response == .OK else { return }
                let paths = panel.urls.map(\.path)
                draft.addFiles(paths)
            }
        }
    }
#endif

private struct FileSelectionChips: View {
    let filePaths: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(filePaths, id: \.self) { path in
                RemovableChip(
                    title: path.filePathDisplayName,
                    removeAccessibilityLabel: "Eliminar archivo",
                    leading: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.secondary)
                    },
                    onRemove: {
                        onRemove(path)
                    }
                )
                .help(path)
            }
        }
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
                accessibilityIdentifier: "project-title-field",
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.05)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15)),
            )
        #else
            TextField(
                "Ej. \"Construir Momentum\"",
                text: $text,
                axis: .vertical,
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
                    .fill(Color.secondary.opacity(0.05)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15)),
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
                        arrowEdge: .top,
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
                            placeholder: "com.ejemplo.app, com.otro.bundle",
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
                RemovableChip(
                    title: app.name,
                    removeAccessibilityLabel: "Eliminar app",
                    leading: {
                        app.icon
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    },
                    onRemove: {
                        selection.remove(app.bundleIdentifier)
                    }
                )
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
                                isSelected: selection.contains(app.bundleIdentifier),
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
