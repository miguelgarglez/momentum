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

        if let domain,
           let match = projects.first(where: { $0.matches(domain: domain) }) {
            return match
        }

        if let bundleIdentifier,
           let match = projects.first(where: { $0.matches(appBundleIdentifier: bundleIdentifier) }) {
            return match
        }

        return nil
    }
}
