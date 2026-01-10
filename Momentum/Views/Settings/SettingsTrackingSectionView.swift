import SwiftUI

struct SettingsTrackingSectionView: View {
    @Binding var draft: TrackerSettingsDraft
    @Binding var showingAutomationInfo: Bool

    #if os(macOS)
        @EnvironmentObject private var automationPermissionManager: AutomationPermissionManager
    #endif

    var body: some View {
        Section("Tracking automático") {
            Text("Controla qué fuentes registra Momentum y la frecuencia de detección.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Registrar dominios web", isOn: $draft.isDomainTrackingEnabled)
            Toggle("Registrar archivos", isOn: $draft.isFileTrackingEnabled)

            #if os(macOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Momentum solo solicita permisos de Automatización cuando necesita rastrear apps donde detecta archivos o dominios. Si los deniegas, puedes reactivarlos desde Ajustes del sistema.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Abrir ajustes de Automatización") {
                            automationPermissionManager.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                        Button("Más info") {
                            showingAutomationInfo = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("automation-permission-info")
                    }
                }
            #endif

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Intervalo de detección")
                    Spacer()
                    Text("\(Int(draft.detectionInterval)) s")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $draft.detectionInterval,
                    in: TrackerSettings.minDetectionInterval ... TrackerSettings.maxDetectionInterval,
                    step: 1,
                )
            }
        }
    }
}
