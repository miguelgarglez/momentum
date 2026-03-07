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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    identityCard
                    whatHappensNextCard
                }
                .padding(FormSheetMetrics.contentPadding)
            }
            .formSheetBackgroundStyle()
            .navigationTitle("Crear proyecto")
            .frame(width: FormSheetMetrics.standardWidth, height: FormSheetMetrics.standardHeight)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear proyecto") {
                        handleCreate()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 50, height: 50)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tu primer proyecto en segundos")
                    .font(.title3.weight(.semibold))

                Text("Crea una base limpia para empezar a medir tiempo sin tener que configurar todo ahora mismo.")
                    .formSupportCopyStyle()
            }

            Spacer()
        }
        .formCardStyle(prominence: .emphasized, padding: 20, cornerRadius: 24)
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Identidad")
                .formSectionHeaderStyle()

            Text("Empieza con nombre e icono. Luego podrás ajustar color, reglas y tracking desde el formulario completo del proyecto.")
                .formSupportCopyStyle()

            VStack(alignment: .leading, spacing: 10) {
                Text("Nombre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                #if os(macOS)
                    LTRTextField(
                        text: $name,
                        placeholder: String(localized: "New cool project"),
                        accessibilityIdentifier: "onboarding-project-name"
                    )
                    .macRoundedTextFieldStyle()
                #else
                    TextField(String(localized: "New cool project"), text: $name)
                        .textFieldStyle(.roundedBorder)
                #endif
            }
            .formCardStyle(prominence: .inset, padding: 16, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    iconPreview

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Icono")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Elige un símbolo que reconozcas rápido en la barra lateral y en los resúmenes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
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
                        accessibilityIdentifier: "onboarding-icon-emoji-system",
                        selection: symbolPickerSelection
                    )

                    Spacer()
                }
            }
            .formCardStyle(prominence: .inset, padding: 16, cornerRadius: 18)
        }
        .formCardStyle()
    }

    private var whatHappensNextCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Qué ocurre ahora")
                .formSectionHeaderStyle()

            VStack(alignment: .leading, spacing: 12) {
                OnboardingStepRow(
                    icon: "play.circle.fill",
                    text: String(localized: "Momentum iniciará Manual en vivo para tu primera sesión en este proyecto.")
                )
                OnboardingStepRow(
                    icon: "clock.badge.plus",
                    text: String(localized: "Después podrás registrar tiempo con auto-tracking, Manual en vivo y Añadir tiempo manual.")
                )
                OnboardingStepRow(
                    icon: "lock.shield.fill",
                    text: String(localized: "Nunca almacenamos contenido, teclas ni capturas de pantalla.")
                )
            }
            .formCardStyle(prominence: .inset, padding: 16, cornerRadius: 18)
        }
        .formCardStyle()
    }

    private func handleCreate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = uniqueProjectName(from: trimmedName)
        let iconName = iconName ?? ProjectIcon.allCases.randomElement()?.systemName ?? ProjectIcon.spark.systemName
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

    private var iconPreview: some View {
        ZStack {
            Circle()
                .fill(Color(hex: ProjectPalette.defaultColor.hex) ?? .accentColor)
                .frame(width: 42, height: 42)
            ProjectIconGlyph(
                name: iconName ?? ProjectIcon.spark.systemName,
                size: 17,
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

private struct OnboardingStepRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
