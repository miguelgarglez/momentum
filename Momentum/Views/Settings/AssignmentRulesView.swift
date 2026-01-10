import SwiftData
import SwiftUI

struct AssignmentRulesView: View {
    @EnvironmentObject private var settings: TrackerSettings
    @EnvironmentObject private var appCatalog: AppCatalog
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AssignmentRule.lastUsedAt, order: .reverse) private var rules: [AssignmentRule]
    @Query(sort: \Project.name, order: .forward) private var projects: [Project]

    @State private var searchText = ""
    @State private var projectFilter: PersistentIdentifier?
    @State private var pendingDeleteRule: AssignmentRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
                backButtonRow
            #endif
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
                            },
                        )
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("assignment-rules-list")
            }
        }
        .padding(.top, 8)
        .padding(.horizontal)
        .padding(.bottom, 12)
        .navigationTitle("Reglas de asignacion")
        #if os(macOS)
            .navigationBarBackButtonHidden(true)
        #endif
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

    #if os(macOS)
        private var backButtonRow: some View {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1),
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Volver")

                Spacer()
            }
        }
    #endif

    private var filterHeader: some View {
        ViewThatFits(in: .horizontal) {
            filterHeaderHorizontal
            filterHeaderVertical
        }
    }

    private var filterHeaderHorizontal: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Buscar")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                searchField
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Filtrar por proyecto")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                projectFilterPicker
            }
        }
    }

    private var filterHeaderVertical: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Buscar")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                searchField
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Filtrar por proyecto")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                projectFilterPicker
            }
        }
    }

    private var searchField: some View {
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

    private var projectFilterPicker: some View {
        Picker("Filtrar por proyecto", selection: $projectFilter) {
            Text("Todos los proyectos")
                .tag(PersistentIdentifier?.none)
            ForEach(projects) { project in
                Text(project.name)
                    .tag(Optional(project.persistentModelID))
            }
        }
        .pickerStyle(.menu)
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
            set: { if !$0 { pendingDeleteRule = nil } },
        )
    }

    private var filteredRules: [AssignmentRule] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = rules.filter { rule in
            let matchesProject: Bool = if let filterID = projectFilter {
                rule.project?.persistentModelID == filterID
            } else {
                true
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
    @EnvironmentObject private var appCatalog: AppCatalog

    let rule: AssignmentRule
    let projects: [Project]
    let isExpired: Bool
    let onDelete: () -> Void

    @State private var selectedProjectID: PersistentIdentifier?
    @State private var hasLoadedSelection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                contextIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(rule.contextLabel): \(contextTitle)")
                        .font(.headline)
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

            HStack(spacing: 10) {
                projectBadge

                Picker("Proyecto", selection: $selectedProjectID) {
                    Text("Sin proyecto")
                        .tag(PersistentIdentifier?.none)
                    ForEach(projects) { project in
                        Text(project.name)
                            .tag(Optional(project.persistentModelID))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            if !hasLoadedSelection {
                selectedProjectID = rule.project?.persistentModelID
                hasLoadedSelection = true
            }
        }
        .onChange(of: selectedProjectID) { _, newValue in
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

    private var contextTitle: String {
        switch AssignmentContextType(rawValue: rule.contextType) {
        case .app:
            appCatalog.app(for: rule.contextValue)?.name ?? rule.contextValue
        case .domain:
            rule.contextValue
        case .file:
            rule.contextValue.filePathDisplayName
        case .none:
            rule.contextValue
        }
    }

    @ViewBuilder
    private var contextIcon: some View {
        let size: CGFloat = 30
        switch AssignmentContextType(rawValue: rule.contextType) {
        case .app:
            #if os(macOS)
                if let app = appCatalog.app(for: rule.contextValue) {
                    app.icon
                        .resizable()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: size, height: size)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            #else
                Image(systemName: "app.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: size, height: size)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            #endif
        case .domain:
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .file:
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .none:
            Image(systemName: "questionmark.circle")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var projectBadge: some View {
        let project = projects.first { $0.persistentModelID == selectedProjectID }
        let color = project?.color ?? Color.secondary.opacity(0.4)
        let iconName = ProjectIcon(rawValue: project?.iconName ?? "")?.systemName ?? "minus"
        return HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(project == nil ? 0.25 : 1))
                    .frame(width: 20, height: 20)
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(project == nil ? Color.secondary : Color.white)
            }
            Text(project?.name ?? "Sin proyecto")
                .font(.subheadline)
                .foregroundStyle(project == nil ? .secondary : .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
