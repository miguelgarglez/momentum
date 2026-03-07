import SwiftUI

private enum ManualTimeEntryInputMode: String, CaseIterable, Identifiable {
    case interval
    case duration

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .interval:
            "Intervalo"
        case .duration:
            "Duración"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .interval:
            "Elige una hora de inicio y otra de fin dentro del mismo día."
        case .duration:
            "Marca el inicio y deja que Momentum calcule el final desde la duración."
        }
    }
}

private enum ManualTimeEntryMotion {
    static let cardSpring = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

struct ManualTimeEntrySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: Project
    let onSaved: (ManualTimeEntrySaveResult) -> Void

    @State private var mode: ManualTimeEntryInputMode = .interval
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var startTime = Date().addingTimeInterval(-3600)
    @State private var endTime = Date()
    @State private var durationMinutes: Double = 60
    @State private var preview: ManualTimeEntryPreview?
    @State private var validationError: String?
    @State private var saveError: String?
    @State private var showOverlapConfirmation = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    modeCard
                    timingCard
                    previewCard

                    if let saveError {
                        ManualTimeEntryMessageCard(
                            title: String(localized: "No pudimos guardar este registro"),
                            message: saveError,
                            tint: .orange,
                            icon: "exclamationmark.triangle.fill"
                        )
                    }
                }
                .padding(FormSheetMetrics.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .formSheetBackgroundStyle()
            .navigationTitle("Añadir tiempo manual")
            .frame(width: FormSheetMetrics.standardWidth, height: FormSheetMetrics.standardHeight)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        handleSaveTapped()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || preview?.effectiveSeconds ?? 0 <= 0)
                    .accessibilityIdentifier("manual-time-save")
                }
            }
        }
        .animation(ManualTimeEntryMotion.cardSpring, value: mode)
        .animation(ManualTimeEntryMotion.cardSpring, value: preview?.effectiveSeconds ?? -1)
        .onAppear {
            refreshPreview()
        }
        .onChange(of: mode) { _, _ in refreshPreview() }
        .onChange(of: selectedDate) { _, _ in refreshPreview() }
        .onChange(of: startTime) { _, _ in refreshPreview() }
        .onChange(of: endTime) { _, _ in refreshPreview() }
        .onChange(of: durationMinutes) { _, _ in refreshPreview() }
        .confirmationDialog(
            "Se ajustará el tiempo por solape",
            isPresented: $showOverlapConfirmation,
            titleVisibility: .visible
        ) {
            Button("Guardar tiempo ajustado") {
                performSave()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            if let preview {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "Has solicitado %@ y se añadirán %@ para evitar solapes."),
                        preview.requestedSeconds.hoursAndMinutesString,
                        preview.effectiveSeconds.hoursAndMinutesString
                    )
                )
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: project.colorHex) ?? .accentColor)
                    .frame(width: 52, height: 52)

                ProjectIconGlyph(
                    name: project.iconName,
                    size: 20,
                    weight: .semibold,
                    symbolStyle: AnyShapeStyle(.white)
                )
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .font(.title3.weight(.semibold))

                Text("Registro manual")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Añade un bloque pasado sin romper la continuidad del tracking ni duplicar tiempo ya asignado.")
                    .formSupportCopyStyle()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(preview?.effectiveSeconds.hoursAndMinutesString ?? "0m")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("tiempo efectivo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formCardStyle(prominence: .emphasized, padding: 20, cornerRadius: 24)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Modo de entrada")
                .formSectionHeaderStyle()

            Text(mode.summary)
                .formSupportCopyStyle()

            VStack(alignment: .leading, spacing: 8) {
                Text("Modo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Modo", selection: $mode) {
                    ForEach(ManualTimeEntryInputMode.allCases) { inputMode in
                        Text(inputMode.title).tag(inputMode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("manual-time-mode-picker")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .formCardStyle()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tiempo")
                .formSectionHeaderStyle()

            VStack(spacing: 0) {
                ManualTimeEntryControlRow("Fecha") {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("manual-time-date")
                }

                Divider()

                ManualTimeEntryControlRow("Hora de inicio") {
                    DatePicker(
                        "",
                        selection: $startTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("manual-time-start")
                }

                Divider()

                if mode == .interval {
                    ManualTimeEntryControlRow("Hora de fin") {
                        DatePicker(
                            "",
                            selection: $endTime,
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                        .accessibilityIdentifier("manual-time-end")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Duración")
                            Spacer()
                            Text(
                                String.localizedStringWithFormat(
                                    String(localized: "%lld min"),
                                    Int64(durationMinutes)
                                )
                            )
                            .monospacedDigit()
                            .formKeyValueStyle(emphasized: true)
                        }

                        Slider(value: $durationMinutes, in: 5 ... 720, step: 5)
                            .accessibilityIdentifier("manual-time-duration-slider")
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 2)
                }
            }
            .formCardStyle(prominence: .inset, padding: 14, cornerRadius: 18)

            if let validationError {
                ManualTimeEntryInlineNote(
                    icon: "exclamationmark.triangle.fill",
                    text: validationError,
                    tint: .orange
                )
            } else {
                ManualTimeEntryInlineNote(
                    icon: "clock.badge.checkmark",
                    text: String(localized: "Solo se permiten horarios pasados. Si hay solape, Momentum lo ajustará antes de guardar."),
                    tint: .secondary
                )
            }
        }
        .formCardStyle()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vista previa")
                .formSectionHeaderStyle()

            if let preview {
                HStack(spacing: 12) {
                    ManualTimePreviewMetric(
                        title: String(localized: "Solicitado"),
                        value: preview.requestedSeconds.hoursAndMinutesString,
                        tint: .secondary,
                        emphasized: false
                    )
                    ManualTimePreviewMetric(
                        title: String(localized: "Solape"),
                        value: preview.overlappedSeconds.hoursAndMinutesString,
                        tint: preview.hasOverlap ? .orange : .secondary,
                        emphasized: preview.hasOverlap
                    )
                    ManualTimePreviewMetric(
                        title: String(localized: "Se guardará"),
                        value: preview.effectiveSeconds.hoursAndMinutesString,
                        tint: .accentColor,
                        emphasized: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if preview.hasOverlap {
                    ManualTimeEntryInlineNote(
                        icon: "arrow.triangle.branch",
                        text: String.localizedStringWithFormat(
                            String(localized: "Hay tiempo ya registrado en este intervalo. Solo se añadirá %@ para evitar duplicados."),
                            preview.effectiveSeconds.hoursAndMinutesString
                        ),
                        tint: .orange
                    )
                } else {
                    ManualTimeEntryInlineNote(
                        icon: "checkmark.circle.fill",
                        text: String(localized: "Todo el bloque está libre y se guardará completo."),
                        tint: .accentColor
                    )
                }
            } else if let validationError {
                ManualTimeEntryMessageCard(
                    title: String(localized: "Necesitamos un rango válido"),
                    message: validationError,
                    tint: .orange,
                    icon: "exclamationmark.triangle.fill"
                )
            } else {
                ManualTimeEntryMessageCard(
                    title: String(localized: "La vista previa aparecerá aquí"),
                    message: String(localized: "Completa el rango y Momentum resumirá el tiempo solicitado, el solape y el total efectivo antes de guardar."),
                    tint: .secondary,
                    icon: "sparkles"
                )
            }
        }
        .formCardStyle()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshPreview() {
        saveError = nil
        guard let interval = requestedInterval() else {
            preview = nil
            return
        }

        let service = ManualTimeEntryService(modelContext: modelContext)
        do {
            preview = try service.preview(for: interval)
            validationError = nil
        } catch {
            preview = nil
            validationError = error.localizedDescription
        }
    }

    private func requestedInterval() -> DateInterval? {
        let calendar = Calendar.current
        let now = Date()

        let day = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        guard let startDate = calendar.date(from: DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: startComponents.hour,
            minute: startComponents.minute
        )) else {
            validationError = String(localized: "No pudimos interpretar la fecha seleccionada.")
            return nil
        }

        if mode == .interval {
            let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            guard let endDate = calendar.date(from: DateComponents(
                year: day.year,
                month: day.month,
                day: day.day,
                hour: endComponents.hour,
                minute: endComponents.minute
            )) else {
                validationError = String(localized: "No pudimos interpretar la hora de fin.")
                return nil
            }
            guard endDate > startDate else {
                validationError = String(localized: "La hora de fin debe ser posterior al inicio.")
                return nil
            }
            guard endDate <= now else {
                validationError = String(localized: "No puedes añadir tiempo en el futuro.")
                return nil
            }
            validationError = nil
            return DateInterval(start: startDate, end: endDate)
        }

        let duration = durationMinutes * 60
        guard duration > 0 else {
            validationError = String(localized: "La duración debe ser mayor que cero.")
            return nil
        }
        let endDate = startDate.addingTimeInterval(duration)
        guard endDate <= now else {
            validationError = String(localized: "No puedes añadir tiempo en el futuro.")
            return nil
        }
        validationError = nil
        return DateInterval(start: startDate, end: endDate)
    }

    private func handleSaveTapped() {
        guard let preview else { return }
        guard preview.effectiveSeconds > 0 else {
            saveError = String(localized: "No hay tiempo disponible para añadir en ese intervalo.")
            return
        }
        if preview.hasOverlap {
            showOverlapConfirmation = true
            return
        }
        performSave()
    }

    private func performSave() {
        guard let interval = requestedInterval() else { return }
        isSaving = true
        defer { isSaving = false }

        let service = ManualTimeEntryService(modelContext: modelContext)
        do {
            let result = try service.save(project: project, interval: interval)
            onSaved(result)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct ManualTimeEntryControlRow<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let control: () -> Content

    init(_ title: LocalizedStringKey, @ViewBuilder control: @escaping () -> Content) {
        self.title = title
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .formKeyValueStyle(emphasized: true)
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 14)
    }
}

private struct ManualTimePreviewMetric: View {
    let title: String
    let value: String
    let tint: Color
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(emphasized ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .formCardStyle(prominence: .inset, padding: 14, cornerRadius: 18)
    }
}

private struct ManualTimeEntryInlineNote: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        FormInlineStatusRow(systemImage: icon, text: text, tint: tint)
    }
}

private struct ManualTimeEntryMessageCard: View {
    let title: String
    let message: String
    let tint: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            ManualTimeEntryInlineNote(
                icon: icon,
                text: message,
                tint: tint
            )
        }
        .formCardStyle(prominence: .inset, padding: 16, cornerRadius: 18)
    }
}
