import SwiftData
import SwiftUI

struct SettingsAssignmentRulesSectionView: View {
    @Binding var draft: TrackerSettingsDraft
    @Query(sort: \AssignmentRule.lastUsedAt, order: .reverse) private var rules: [AssignmentRule]
    private let shortSessionOptions: [AssignmentRuleExpirationOption] = [.minutes15, .minutes30, .hour1, .hours4, .hours8]
    private let longTermOptions: [AssignmentRuleExpirationOption] = [.day1, .days7, .days30, .days60, .days90]

    var body: some View {
        Section {
            if rules.isEmpty {
                Text("Sin reglas guardadas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Expiración de reglas", selection: $draft.assignmentRuleExpiration) {
                Section(String(localized: "Sin caducidad")) {
                    Text(AssignmentRuleExpirationOption.never.label)
                        .tag(AssignmentRuleExpirationOption.never)
                }

                Section(String(localized: "Sesión corta")) {
                    ForEach(shortSessionOptions) { option in
                        Text(option.label)
                            .tag(option)
                    }
                }

                Section(String(localized: "Largo plazo")) {
                    ForEach(longTermOptions) { option in
                        Text(option.label)
                            .tag(option)
                    }
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
