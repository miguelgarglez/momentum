import SwiftUI
import SwiftData

struct AssignmentRulesView: View {
    @EnvironmentObject private var settings: TrackerSettings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AssignmentRule.lastUsedAt, order: .reverse) private var rules: [AssignmentRule]
    @Query(sort: \Project.name, order: .forward) private var projects: [Project]

    @State private var searchText = ""
    @State private var projectFilter: PersistentIdentifier?
    @State private var pendingDeleteRule: AssignmentRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            filterHeader

            if filteredRules.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredRules) { rule in
                        AssignmentRuleRow(
                            rule: rule,
                            projects: projects,
                            isExpired: isExpired(rule),
                            onDelete: {
                                pendingDeleteRule = rule
                            }
                        )
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("assignment-rules-list")
            }
        }
        .padding()
        .navigationTitle("Reglas de asignacion")
        .confirmationDialog("¿Eliminar regla?", isPresented: deleteConfirmationBinding, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                deletePendingRule()
            }
            Button("Cancelar", role: .cancel) {
                pendingDeleteRule = nil
            }
        } message: {
            if let pendingDeleteRule {
                Text("Eliminar la regla para \(pendingDeleteRule.contextLabel.lowercased()) \(pendingDeleteRule.contextValue)?")
            }
        }
    }

    private var filterHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Buscar")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
#if os(macOS)
                LTRTextField(text: $searchText, placeholder: "Contexto o proyecto")
                    .macRoundedTextFieldStyle()
                    .accessibilityIdentifier("assignment-rules-search-field")
#else
                TextField("Contexto o proyecto", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("assignment-rules-search-field")
#endif
            }

            Picker("Filtrar por proyecto", selection: $projectFilter) {
                Text("Todos los proyectos")
                    .tag(Optional<PersistentIdentifier>.none)
                ForEach(projects) { project in
                    Text(project.name)
                        .tag(Optional(project.persistentModelID))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No hay reglas guardadas")
                .font(.headline)
            Text("Cuando resuelvas conflictos se guardaran aqui.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteRule != nil },
            set: { if !$0 { pendingDeleteRule = nil } }
        )
    }

    private var filteredRules: [AssignmentRule] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = rules.filter { rule in
            let matchesProject: Bool
            if let filterID = projectFilter {
                matchesProject = rule.project?.persistentModelID == filterID
            } else {
                matchesProject = true
            }

            let matchesSearch: Bool
            if trimmedSearch.isEmpty {
                matchesSearch = true
            } else {
                let needle = trimmedSearch.lowercased()
                let contextMatch = rule.contextValue.lowercased().contains(needle)
                let projectMatch = rule.project?.name.lowercased().contains(needle) ?? false
                matchesSearch = contextMatch || projectMatch
            }

            return matchesProject && matchesSearch
        }

        return filtered.sorted { lhs, rhs in
            let lhsExpired = isExpired(lhs)
            let rhsExpired = isExpired(rhs)
            if lhsExpired != rhsExpired {
                return !lhsExpired
            }
            return lhs.effectiveLastUsedAt > rhs.effectiveLastUsedAt
        }
    }

    private func isExpired(_ rule: AssignmentRule) -> Bool {
        guard let cutoff = settings.assignmentRuleExpiration.cutoffDate() else { return false }
        return rule.effectiveLastUsedAt < cutoff
    }

    @MainActor
    private func deletePendingRule() {
        guard let pendingDeleteRule else { return }
        modelContext.delete(pendingDeleteRule)
        try? modelContext.save()
        self.pendingDeleteRule = nil
    }
}

private struct AssignmentRuleRow: View {
    @Environment(\.modelContext) private var modelContext

    let rule: AssignmentRule
    let projects: [Project]
    let isExpired: Bool
    let onDelete: () -> Void

    @State private var selectedProjectID: PersistentIdentifier?
    @State private var hasLoadedSelection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(rule.contextLabel): \(rule.contextValue)")
                        .font(.headline)
                    if let projectName = rule.project?.name {
                        Text(projectName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Proyecto eliminado")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if isExpired {
                        Text("Expirada")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Text(lastUsedText(for: rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Picker("Proyecto", selection: $selectedProjectID) {
                    Text("Sin proyecto")
                        .tag(Optional<PersistentIdentifier>.none)
                    ForEach(projects) { project in
                        Text(project.name)
                            .tag(Optional(project.persistentModelID))
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Button("Eliminar", role: .destructive) {
                    onDelete()
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if !hasLoadedSelection {
                selectedProjectID = rule.project?.persistentModelID
                hasLoadedSelection = true
            }
        }
        .onChange(of: selectedProjectID) { newValue in
            guard hasLoadedSelection else { return }
            guard newValue != rule.project?.persistentModelID else { return }
            updateRuleProject(to: newValue)
        }
    }

    private func updateRuleProject(to projectID: PersistentIdentifier?) {
        let project = projects.first { $0.persistentModelID == projectID }
        rule.project = project
        rule.lastUsedAt = .now
        try? modelContext.save()
    }

    private func lastUsedText(for rule: AssignmentRule) -> String {
        let formatter = RelativeDateTimeFormatter()
        let relative = formatter.localizedString(for: rule.effectiveLastUsedAt, relativeTo: .now)
        return "Ultimo uso: \(relative)"
    }
}
