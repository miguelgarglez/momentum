//
//  OnboardingQuickProjectView.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftData
import SwiftUI

struct OnboardingQuickProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var onboardingState: OnboardingState
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .forward)])
    private var projects: [Project]

    @State private var name: String = ""
    @State private var iconName: String?
    @State private var isIconPickerPresented = false

    let onComplete: (Project) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Nuevo proyecto") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nombre opcional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        #if os(macOS)
                            LTRTextField(
                                text: $name,
                                placeholder: "New cool project",
                                accessibilityIdentifier: "onboarding-project-name",
                            )
                            .macRoundedTextFieldStyle()
                        #else
                            TextField("New cool project", text: $name)
                                .textFieldStyle(.roundedBorder)
                        #endif
                    }

                    HStack(alignment: .center, spacing: 12) {
                        iconPreview

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
                            title: "Elegir emoji",
                            accessibilityIdentifier: "onboarding-icon-emoji-system",
                            selection: symbolPickerSelection
                        )

                        Spacer()
                    }
                }

                Section("Qué ocurre ahora") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Al crear el proyecto, Momentum iniciará Manual en vivo para tu primera sesión en este proyecto.")
                            .font(.subheadline)
                        Text("Después podrás registrar tiempo de 3 formas: Auto-tracking, Manual en vivo y Añadir tiempo manual.")
                            .font(.subheadline)
                        Text("Nunca almacenamos contenido, teclas ni capturas de pantalla.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Crear proyecto")
            .frame(minWidth: 440, maxWidth: 540, minHeight: 320)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear proyecto") {
                        handleCreate()
                    }
                }
            }
        }
    }

    private func handleCreate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = uniqueProjectName(from: trimmedName)
        let iconName = iconName ?? ProjectIcon.allCases.randomElement()?.systemName ?? ProjectIcon.spark.systemName
        let project = Project(
            name: projectName,
            colorHex: ProjectPalette.defaultColor.hex,
            iconName: iconName,
        )
        modelContext.insert(project)
        do {
            try modelContext.save()
            onboardingState.markProjectCreated()
            onComplete(project)
            dismiss()
        } catch {
            dismiss()
        }
    }

    private var iconPreview: some View {
        ZStack {
            Circle()
                .fill(Color(hex: ProjectPalette.defaultColor.hex) ?? .accentColor)
                .frame(width: 36, height: 36)
            ProjectIconGlyph(
                name: iconName ?? ProjectIcon.spark.systemName,
                size: 14,
                weight: .semibold,
                symbolStyle: AnyShapeStyle(.white)
            )
        }
        .accessibilityHidden(true)
    }

    private var symbolPickerSelection: Binding<String> {
        Binding(
            get: { iconName ?? ProjectIcon.spark.systemName },
            set: { iconName = $0 }
        )
    }

    private func uniqueProjectName(from baseName: String) -> String {
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
}
