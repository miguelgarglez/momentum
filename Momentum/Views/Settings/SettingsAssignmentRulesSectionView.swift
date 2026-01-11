import SwiftUI

struct SettingsAssignmentRulesSectionView: View {
    @Binding var draft: TrackerSettingsDraft

    var body: some View {
        Section {
            Picker("Expiración de reglas", selection: $draft.assignmentRuleExpiration) {
                ForEach(AssignmentRuleExpirationOption.allCases) { option in
                    Text(option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("assignment-rules-expiration-picker")

            NavigationLink("Gestionar reglas de asignacion") {
                AssignmentRulesView()
            }
            .accessibilityIdentifier("assignment-rules-link")

            Text("Las reglas expiradas se eliminan automáticamente, y podrás reinstalarlas al resolver un conflicto.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            SettingsSectionHeader(
                "Reglas de asignacion",
                subtitle: "Configura cómo se asignan automáticamente las sesiones a proyectos.",
            )
        }
    }
}
