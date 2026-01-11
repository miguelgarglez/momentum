import SwiftData
import SwiftUI

struct SettingsAssignmentRulesSectionView: View {
    @Binding var draft: TrackerSettingsDraft
    @Query(sort: \AssignmentRule.lastUsedAt, order: .reverse) private var rules: [AssignmentRule]

    var body: some View {
        Section {
            if rules.isEmpty {
                Text("Sin reglas guardadas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                "Reglas",
                subtitle: "Configura cómo se asignan automáticamente las sesiones a proyectos.",
            )
        }
    }
}
