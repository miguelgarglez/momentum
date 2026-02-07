//
//  ManualTrackingSheetView.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftData
import SwiftUI

enum ManualTrackingSheetInitialMode {
    case automatic
    case existing
    case new
}

struct ManualTrackingSheetView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case existing
        case new

        var id: String { rawValue }
        var title: LocalizedStringResource {
            switch self {
            case .existing: "Existente"
            case .new: "Nuevo"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let projects: [Project]
    let onStartExisting: (Project) -> Void
    let onCreateAndStart: (ManualTrackingNewProjectDraft) -> Void

    @State private var mode: Mode
    @State private var selectedProjectID: PersistentIdentifier?
    @State private var newProjectName: String = ""
    @State private var newProjectIconName: String?
    @State private var isIconPickerPresented = false

    init(
        projects: [Project],
        onStartExisting: @escaping (Project) -> Void,
        onCreateAndStart: @escaping (ManualTrackingNewProjectDraft) -> Void,
        initialMode: ManualTrackingSheetInitialMode = .automatic,
    ) {
        self.projects = projects
        self.onStartExisting = onStartExisting
        self.onCreateAndStart = onCreateAndStart
        let resolvedMode: Mode = switch initialMode {
        case .automatic:
            projects.isEmpty ? .new : .existing
        case .existing:
            projects.isEmpty ? .new : .existing
        case .new:
            .new
        }
        _mode = State(initialValue: resolvedMode)
        _selectedProjectID = State(initialValue: projects.first?.persistentModelID)
        _newProjectIconName = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Modo") {
                    Picker("Modo", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .existing {
                    Section("Proyecto existente") {
                        if projects.isEmpty {
                            Text("No tienes proyectos aún.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Proyecto", selection: $selectedProjectID) {
                                ForEach(projects) { project in
                                    Text(project.name)
                                        .tag(Optional(project.persistentModelID))
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("manual-tracking-project-picker")
                        }
                    }
                } else {
                    Section("Crear rápido") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nombre opcional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            #if os(macOS)
                                LTRTextField(
                                    text: $newProjectName,
                                    placeholder: String(localized: "New cool project"),
                                    accessibilityIdentifier: "manual-tracking-project-name",
                                )
                                .macRoundedTextFieldStyle()
                            #else
                                TextField("New cool project", text: $newProjectName)
                                    .textFieldStyle(.roundedBorder)
                            #endif
                        }

                        Picker("Icono", selection: $newProjectIconName) {
                            Text("Aleatorio")
                                .tag(String?.none)
                            ForEach(ProjectIcon.allCases, id: \.self) { icon in
                                Label(icon.displayName, systemImage: icon.systemName)
                                    .tag(Optional(icon.systemName))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("manual-tracking-icon-picker")

                        Button {
                            isIconPickerPresented.toggle()
                        } label: {
                            Label("Iconos del sistema", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(.bordered)
                        .popover(
                            isPresented: $isIconPickerPresented,
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .top
                        ) {
                            ProjectIconPickerPopoverView(selection: symbolPickerSelection, onDismiss: {
                                isIconPickerPresented = false
                            })
                        }

                        SystemEmojiPickerButton(
                            title: String(localized: "Elegir emoji"),
                            accessibilityIdentifier: "manual-tracking-icon-emoji-system",
                            selection: symbolPickerSelection
                        )

                        iconPreview
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Tracking manual")
            .frame(minWidth: 420, maxWidth: 520)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar") {
                        handleStart()
                    }
                    .disabled(mode == .existing && selectedProjectID == nil)
                }
            }
        }
    }

    private func handleStart() {
        switch mode {
        case .existing:
            guard let selectedProjectID,
                  let project = projects.first(where: { $0.persistentModelID == selectedProjectID })
            else {
                return
            }
            onStartExisting(project)
        case .new:
            let draft = ManualTrackingNewProjectDraft(name: newProjectName, iconName: newProjectIconName)
            onCreateAndStart(draft)
        }
        dismiss()
    }

    private var symbolPickerSelection: Binding<String> {
        Binding(
            get: { newProjectIconName ?? ProjectIcon.spark.systemName },
            set: { newProjectIconName = $0 }
        )
    }

    private var iconPreview: some View {
        ZStack {
            Circle()
                .fill(Color(hex: ProjectPalette.defaultColor.hex) ?? .accentColor)
                .frame(width: 32, height: 32)
            ProjectIconGlyph(
                name: newProjectIconName ?? ProjectIcon.spark.systemName,
                size: 13,
                weight: .semibold,
                symbolStyle: AnyShapeStyle(.white)
            )
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    guard let container = try? ModelContainer(
        for: Project.self,
        TrackingSession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
    ) else {
        fatalError("Failed to create preview ModelContainer.")
    }
    let sample = Project(name: "Proyecto Manual")
    container.mainContext.insert(sample)

    return ManualTrackingSheetView(
        projects: [sample],
        onStartExisting: { _ in },
        onCreateAndStart: { _ in },
    )
    .modelContainer(container)
}
