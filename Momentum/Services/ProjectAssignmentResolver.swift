import Foundation
import SwiftData

@MainActor
protocol ProjectAssignmentResolving {
    func resolveProject(for bundleIdentifier: String?, domain: String?, filePath: String?) -> Project?
    func resolveAssignment(for bundleIdentifier: String?, domain: String?, filePath: String?) -> AssignmentResult
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
    private let cache = Cache()
    private let projectsCacheTTL: TimeInterval = 5
    private let ruleCacheTTL: TimeInterval = 5

    init(modelContainer: ModelContainer, settings: TrackerSettings) {
        self.modelContainer = modelContainer
        self.settings = settings
    }

    func resolveProject(for bundleIdentifier: String?, domain: String?, filePath: String?) -> Project? {
        switch resolveAssignment(for: bundleIdentifier, domain: domain, filePath: filePath) {
        case let .assigned(project, _):
            project
        case .conflict, .none:
            nil
        }
    }

    func resolveAssignment(for bundleIdentifier: String?, domain: String?, filePath: String?) -> AssignmentResult {
        guard let projects = fetchProjects() else {
            return .none
        }

        if let context = normalizedFileContext(from: filePath) {
            let candidates = projects.filter { $0.matches(filePath: context.value) }
            return resolve(context: context, candidates: candidates, allProjects: projects)
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
        if let lastFetch = cache.lastProjectsFetch,
           Date().timeIntervalSince(lastFetch) < projectsCacheTTL
        {
            return cache.projects
        }
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\Project.createdAt, order: .forward)],
        )
        guard let projects = try? Diagnostics.record(.swiftDataFetch, work: {
            try modelContainer.mainContext.fetch(descriptor)
        }) else { return nil }
        cache.projects = projects
        cache.lastProjectsFetch = Date()
        return projects
    }

    private func resolve(
        context: AssignmentContext,
        candidates: [Project],
        allProjects _: [Project],
    ) -> AssignmentResult {
        if let rule = fetchRule(for: context) {
            if isExpired(rule) {
                if !RuntimeFlags.isDisabled(.disableSwiftDataWrites) {
                    modelContainer.mainContext.delete(rule)
                    try? Diagnostics.record(.swiftDataSave) {
                        try modelContainer.mainContext.save()
                    }
                }
            } else if let ruleProject = rule.project {
                if !RuntimeFlags.isDisabled(.disableSwiftDataWrites) {
                    rule.lastUsedAt = .now
                    try? Diagnostics.record(.swiftDataSave) {
                        try modelContainer.mainContext.save()
                    }
                }
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
        let cacheKey = cacheKeyForRule(context)
        if let cached = cache.rules[cacheKey],
           let cachedAt = cache.ruleFetchTimestamps[cacheKey],
           Date().timeIntervalSince(cachedAt) < ruleCacheTTL
        {
            return cached
        }
        let typeValue = context.type.rawValue
        let contextValue = context.value
        let descriptor = FetchDescriptor<AssignmentRule>(
            predicate: #Predicate {
                $0.contextType == typeValue &&
                    $0.contextValue == contextValue
            },
        )
        let rule = try? Diagnostics.record(.swiftDataFetch, work: {
            try modelContainer.mainContext.fetch(descriptor).first
        })
        cache.rules[cacheKey] = rule
        cache.ruleFetchTimestamps[cacheKey] = Date()
        return rule
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

    private func normalizedFileContext(from filePath: String?) -> AssignmentContext? {
        let normalized = filePath?.normalizedFilePath
        guard let normalized, !normalized.isEmpty else { return nil }
        return AssignmentContext(type: .file, value: normalized)
    }

    private func normalizedAppContext(from bundleIdentifier: String?) -> AssignmentContext? {
        let normalized = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return nil }
        return AssignmentContext(type: .app, value: normalized)
    }

    private func cacheKeyForRule(_ context: AssignmentContext) -> String {
        "\(context.type.rawValue)|\(context.value)"
    }
}

private extension ProjectAssignmentResolver {
    final class Cache {
        var projects: [Project] = []
        var lastProjectsFetch: Date?
        var rules: [String: AssignmentRule?] = [:]
        var ruleFetchTimestamps: [String: Date] = [:]
    }
}
