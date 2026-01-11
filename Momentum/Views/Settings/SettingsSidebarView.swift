import SwiftData
import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selection: SettingsSection?
    let draft: TrackerSettingsDraft
    @Query(sort: \AssignmentRule.lastUsedAt, order: .reverse) private var rules: [AssignmentRule]

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.allCases) { section in
                NavigationLink(value: section) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(section.label, systemImage: section.systemImageName)
                            .font(.headline)
                        if let preview = previewText(for: section), section != selection {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .focusable(true)
                .accessibilityLabel(Text(section.label))
                .accessibilityHint(Text("Abre la sección \(section.label)."))
            }
        }
        .listStyle(.sidebar)
    }

    private func previewText(for section: SettingsSection) -> String? {
        switch section {
        case .exclusions:
            guard draft.excludedApps.isEmpty,
                  draft.excludedDomains.isEmpty,
                  draft.excludedFiles.isEmpty
            else { return nil }
            return "Sin exclusiones configuradas."
        case .assignmentRules:
            return rules.isEmpty ? "Sin reglas guardadas." : nil
        case .tracking, .privacy, .appearance, .idle:
            return nil
        }
    }
}

#Preview {
    SettingsSidebarView(
        selection: .constant(.tracking),
        draft: TrackerSettingsDraft(),
    )
}
