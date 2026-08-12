import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            Section("Inactividad") {
                Toggle("Pausar cronómetro por inactividad", isOn: idleEnabledBinding)
                Stepper(
                    value: idleMinutesBinding,
                    in: 1 ... 30
                ) {
                    Text("Umbral: \(environment.settings.idleThresholdMinutes) min")
                }
                Text("Usa el tiempo de inactividad del sistema (sin permisos extra).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Atajos") {
                LabeledContent("Alternar foco (último proyecto)", value: "⌃⌥⌘M")
            }

            Section("Acerca de") {
                LabeledContent("Momentum", value: "Focus Session v0")
                Text("Sesiones intencionales. Números fiables. Sin magia.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
    }

    private var idleEnabledBinding: Binding<Bool> {
        Binding(
            get: { environment.settings.isIdlePauseEnabled },
            set: { newValue in
                environment.settings.isIdlePauseEnabled = newValue
                environment.applySettings()
            }
        )
    }

    private var idleMinutesBinding: Binding<Int> {
        Binding(
            get: { environment.settings.idleThresholdMinutes },
            set: { newValue in
                environment.settings.idleThresholdMinutes = newValue
                environment.applySettings()
            }
        )
    }
}
