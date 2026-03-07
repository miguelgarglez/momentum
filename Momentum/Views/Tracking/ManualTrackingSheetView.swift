import SwiftData
import SwiftUI

enum ManualTrackingSheetInitialMode {
    case automatic
    case existing
    case new
}

private enum ManualTrackingSheetMotion {
    static let sectionSpring = Animation.spring(response: 0.32, dampingFraction: 0.88)
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

        var description: LocalizedStringResource {
            switch self {
            case .existing:
                "Usa un proyecto ya creado para arrancar al instante."
            case .new:
                "Crea un proyecto mínimo y empieza a contar tiempo en el mismo paso."
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    modeCard

                    if mode == .existing {
                        existingProjectCard
                    } else {
                        quickCreateCard
                    }
                }
                .padding(FormSheetMetrics.contentPadding)
            }
            .formSheetBackgroundStyle()
            .navigationTitle("Manual en vivo")
            .frame(width: FormSheetMetrics.standardWidth, height: FormSheetMetrics.standardHeight)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Iniciar") {
                        handleStart()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(mode == .existing && selectedProjectID == nil)
                }
            }
        }
        .animation(ManualTrackingSheetMotion.sectionSpring, value: mode)
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 50, height: 50)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Arranca una sesión manual al momento")
                    .font(.title3.weight(.semibold))

                Text("Elige un proyecto existente o crea uno mínimo. Podrás completar color, apps, dominios y archivos más tarde.")
                    .formSupportCopyStyle()
            }

            Spacer()

            Text(projects.isEmpty ? "Nuevo" : "\(projects.count)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .formCardStyle(prominence: .inset, padding: 0, cornerRadius: 14)
        }
        .formCardStyle(prominence: .emphasized, padding: 20, cornerRadius: 24)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Modo")
                .formSectionHeaderStyle()

            Text(mode.description)
                .formSupportCopyStyle()

            Picker("Modo", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .formCardStyle()
    }

    private var existingProjectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Proyecto existente")
                .formSectionHeaderStyle()

            if projects.isEmpty {
                ManualTrackingInfoRow(
                    icon: "folder.badge.plus",
                    text: String(localized: "Todavía no tienes proyectos. Cambia al modo Nuevo para crear uno en este mismo flujo."),
                    tint: .secondary
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Proyecto", selection: $selectedProjectID) {
                        ForEach(projects) { project in
                            Text(project.name)
                                .tag(Optional(project.persistentModelID))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityIdentifier("manual-tracking-project-picker")

                    ManualTrackingInfoRow(
                        icon: "clock.arrow.circlepath",
                        text: String(localized: "La sesión empezará inmediatamente en el proyecto seleccionado."),
                        tint: .secondary
                    )
                }
                .formCardStyle(prominence: .inset, padding: 16, cornerRadius: 18)
            }
        }
        .formCardStyle()
    }

    private var quickCreateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Crear rápido")
                .formSectionHeaderStyle()

            Text("Lo mínimo para arrancar: nombre opcional e icono. Todo lo demás se puede completar después.")
                .formSupportCopyStyle()

            VStack(alignment: .leading, spacing: 10) {
                Text("Nombre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                #if os(macOS)
                    LTRTextField(
                        text: $newProjectName,
                        placeholder: String(localized: "New cool project"),
                        accessibilityIdentifier: "manual-tracking-project-name"
                    )
                    .macRoundedTextFieldStyle()
                #else
                    TextField("New cool project", text: $newProjectName)
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
                        Text("Puedes dejar uno aleatorio o elegir un símbolo más reconocible para empezar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
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
                }
            }
            .formCardStyle(prominence: .inset, padding: 16, cornerRadius: 18)
        }
        .formCardStyle()
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
                .frame(width: 42, height: 42)
            ProjectIconGlyph(
                name: newProjectIconName ?? ProjectIcon.spark.systemName,
                size: 17,
                weight: .semibold,
                symbolStyle: AnyShapeStyle(.white)
            )
        }
        .accessibilityHidden(true)
    }
}

private struct ManualTrackingInfoRow: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    guard let container = try? ModelContainer(
        for: Project.self,
        TrackingSession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) else {
        fatalError("Failed to create preview ModelContainer.")
    }
    let sample = Project(name: "Proyecto Manual")
    container.mainContext.insert(sample)

    return ManualTrackingSheetView(
        projects: [sample],
        onStartExisting: { _ in },
        onCreateAndStart: { _ in }
    )
    .modelContainer(container)
}
