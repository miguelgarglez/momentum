import SwiftUI

struct TrackerSettingsView: View {
    @EnvironmentObject private var settings: TrackerSettings
    @Environment(\.dismiss) private var dismiss

    @State private var draft = TrackerSettingsDraft()

    init() {}

    var body: some View {
        NavigationStack {
            Form {
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
                        Text("Momentum pausará el tracking tras este tiempo sin actividad.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Configuración")
            .frame(minWidth: 300)
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 12) {
                    Button("Cerrar") { dismiss() }
                    Button("Guardar") {
                        applyChanges()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            draft = TrackerSettingsDraft(from: settings)
        }
    }

    @MainActor
    private func applyChanges() {
        settings.isDomainTrackingEnabled = draft.isDomainTrackingEnabled
        settings.detectionInterval = draft.detectionInterval
        settings.idleThresholdMinutes = draft.idleThresholdMinutes
    }
}

@MainActor
private struct TrackerSettingsDraft {
    var detectionInterval: Double
    var idleThresholdMinutes: Int
    var isDomainTrackingEnabled: Bool

    init(from settings: TrackerSettings) {
        detectionInterval = settings.detectionInterval
        idleThresholdMinutes = settings.idleThresholdMinutes
        isDomainTrackingEnabled = settings.isDomainTrackingEnabled
    }

    init() {
        detectionInterval = TrackerSettings.minDetectionInterval
        idleThresholdMinutes = 15
        isDomainTrackingEnabled = true
    }
}
