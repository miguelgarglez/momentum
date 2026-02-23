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
            Form {
                Section("Modo de entrada") {
                    Picker("Modo", selection: $mode) {
                        ForEach(ManualTimeEntryInputMode.allCases) { inputMode in
                            Text(inputMode.title).tag(inputMode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("manual-time-mode-picker")
                }

                Section("Tiempo") {
                    DatePicker(
                        "Fecha",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date],
                    )
                    .accessibilityIdentifier("manual-time-date")

                    DatePicker(
                        "Hora de inicio",
                        selection: $startTime,
                        displayedComponents: [.hourAndMinute],
                    )
                    .accessibilityIdentifier("manual-time-start")

                    if mode == .interval {
                        DatePicker(
                            "Hora de fin",
                            selection: $endTime,
                            displayedComponents: [.hourAndMinute],
                        )
                        .accessibilityIdentifier("manual-time-end")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Duración")
                                Spacer()
                                Text(
                                    String.localizedStringWithFormat(
                                        String(localized: "%lld min"),
                                        Int64(durationMinutes)
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                            Slider(value: $durationMinutes, in: 5 ... 720, step: 5)
                                .accessibilityIdentifier("manual-time-duration-slider")
                        }
                    }
                }

                Section("Vista previa") {
                    if let preview {
                        PreviewRow(title: "Tiempo solicitado", value: preview.requestedSeconds.hoursAndMinutesString)
                        PreviewRow(title: "Solape detectado", value: preview.overlappedSeconds.hoursAndMinutesString)
                        PreviewRow(title: "Tiempo efectivo", value: preview.effectiveSeconds.hoursAndMinutesString)
                    } else if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Completa un rango válido para calcular la vista previa.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Añadir tiempo manual")
            .frame(minWidth: 460, maxWidth: 560)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        handleSaveTapped()
                    }
                    .disabled(isSaving || preview?.effectiveSeconds ?? 0 <= 0)
                    .accessibilityIdentifier("manual-time-save")
                }
            }
        }
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
                        preview.effectiveSeconds.hoursAndMinutesString,
                    )
                )
            }
        }
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

private struct PreviewRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }
}
