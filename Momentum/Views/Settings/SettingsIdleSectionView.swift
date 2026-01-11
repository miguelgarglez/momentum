import SwiftUI

struct SettingsIdleSectionView: View {
    @Binding var draft: TrackerSettingsDraft

    var body: some View {
        Section("Inactividad") {
            Text("Define cuándo considerar una sesión inactiva y pausar el registro.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Stepper(
                    value: $draft.idleThresholdMinutes,
                    in: TrackerSettings.minIdleMinutes ... TrackerSettings.maxIdleMinutes,
                ) {
                    HStack {
                        Text("Umbral de inactividad")
                        Spacer()
                        Text("\(draft.idleThresholdMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Momentum pausará el tracking tras este tiempo sin interacción.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
