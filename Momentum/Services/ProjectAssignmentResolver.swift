import Foundation
import SwiftData

@MainActor
protocol ProjectAssignmentResolving {
    func resolveProject(for bundleIdentifier: String?, domain: String?) -> Project?
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

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func resolveProject(for bundleIdentifier: String?, domain: String?) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [
                SortDescriptor(\Project.priority, order: .reverse),
                SortDescriptor(\Project.createdAt, order: .forward)
            ]
        )
        guard let projects = try? modelContainer.mainContext.fetch(descriptor) else {
            return nil
        }

        let normalizedDomain = domain?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalizedDomain, !normalizedDomain.isEmpty {
            // When a domain is available we only consider explicit domain assignments.
            if let match = projects.first(where: { $0.matches(domain: normalizedDomain) }) {
                return match
            }
            return nil
        }

        guard let bundleIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return nil
        }

        if let match = projects.first(where: { $0.matches(appBundleIdentifier: bundleIdentifier) }) {
            return match
        }

        return nil
    }
}
