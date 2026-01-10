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
    @State private var icon: ProjectIcon?

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
                                accessibilityIdentifier: "onboarding-project-name"
                            )
                            .macRoundedTextFieldStyle()
                        #else
                            TextField("New cool project", text: $name)
                                .textFieldStyle(.roundedBorder)
                        #endif
                    }

                    Picker("Icono", selection: $icon) {
                        Text("Aleatorio")
                            .tag(ProjectIcon?.none)
                        ForEach(ProjectIcon.allCases, id: \.self) { icon in
                            Label(icon.displayName, systemImage: icon.systemName)
                                .tag(Optional(icon))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("onboarding-icon-picker")
                }

                Section("Qué ocurre ahora") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Al crear el proyecto, Momentum empezará a trackear tu actividad desde este momento y registrará las apps y dominios que uses para asociarlos automáticamente.")
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
        let iconName = icon?.systemName ?? ProjectIcon.allCases.randomElement()?.systemName ?? ProjectIcon.spark.systemName
        let project = Project(
            name: projectName,
            colorHex: ProjectPalette.defaultColor.hex,
            iconName: iconName
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
