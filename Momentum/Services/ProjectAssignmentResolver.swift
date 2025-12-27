import Foundation
import SwiftData

@MainActor
protocol ProjectAssignmentResolving {
    func resolveProject(for bundleIdentifier: String?, domain: String?) -> Project?
    func resolveAssignment(for bundleIdentifier: String?, domain: String?) -> AssignmentResult
}

/// Encapsulates the rules for routing tracked sessions to projects.
///
/// `ProjectAssignmentResolver` takes bundle identifiers and optional browser
/// domains and chooses the most appropriate `Project` according to the user’s
/// assignments (apps, domains, or both). Extracting this logic keeps
/// `ActivityTracker` focused on orchestration instead of routing heuristics.
@MainActor
struct ProjectAssignmentResolver: ProjectAssignmentResolving {
    private let modelContainer: ModelContainer
    private let settings: TrackerSettings

    init(modelContainer: ModelContainer, settings: TrackerSettings) {
        self.modelContainer = modelContainer
        self.settings = settings
    }

    func resolveProject(for bundleIdentifier: String?, domain: String?) -> Project? {
        switch resolveAssignment(for: bundleIdentifier, domain: domain) {
        case let .assigned(project, _):
            return project
        case .conflict, .none:
            return nil
        }
    }

    func resolveAssignment(for bundleIdentifier: String?, domain: String?) -> AssignmentResult {
        guard let projects = fetchProjects() else {
            return .none
        }

        if let context = normalizedDomainContext(from: domain) {
            let candidates = projects.filter { $0.matches(domain: context.value) }
            return resolve(context: context, candidates: candidates, allProjects: projects)
        }

        if let context = normalizedAppContext(from: bundleIdentifier) {
            let candidates = projects.filter { $0.matches(appBundleIdentifier: context.value) }
            return resolve(context: context, candidates: candidates, allProjects: projects)
        }

        return .none
    }

    private func fetchProjects() -> [Project]? {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\Project.createdAt, order: .forward)]
        )
        return try? modelContainer.mainContext.fetch(descriptor)
    }

    private func resolve(
        context: AssignmentContext,
        candidates: [Project],
        allProjects: [Project]
    ) -> AssignmentResult {
        if let rule = fetchRule(for: context) {
            if isExpired(rule) {
                modelContainer.mainContext.delete(rule)
                try? modelContainer.mainContext.save()
            } else if let ruleProject = rule.project {
                rule.lastUsedAt = .now
                try? modelContainer.mainContext.save()
                return .assigned(ruleProject, usedRule: true)
            }
        }

        guard !candidates.isEmpty else { return .none }
        guard candidates.count > 1 else {
            return .assigned(candidates[0], usedRule: false)
        }
        return .conflict(context, candidates: candidates)
    }

    private func fetchRule(for context: AssignmentContext) -> AssignmentRule? {
        let typeValue = context.type.rawValue
        let contextValue = context.value
        let descriptor = FetchDescriptor<AssignmentRule>(
            predicate: #Predicate {
                $0.contextType == typeValue &&
                $0.contextValue == contextValue
            }
        )
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    private func isExpired(_ rule: AssignmentRule) -> Bool {
        guard let cutoff = settings.assignmentRuleExpiration.cutoffDate() else { return false }
        return rule.effectiveLastUsedAt < cutoff
    }

    private func normalizedDomainContext(from domain: String?) -> AssignmentContext? {
        let normalized = domain?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return AssignmentContext(type: .domain, value: normalized)
    }

    private func normalizedAppContext(from bundleIdentifier: String?) -> AssignmentContext? {
        let normalized = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return nil }
        return AssignmentContext(type: .app, value: normalized)
    }
}
