import SwiftData

struct OnboardingTrackingStarter {
    private(set) var pendingProjectID: PersistentIdentifier?

    mutating func queue(projectID: PersistentIdentifier) {
        pendingProjectID = projectID
    }

    mutating func handleNotification(
        projectID: PersistentIdentifier,
        startTracking: Bool,
        projects: [Project]
    ) -> Project? {
        guard startTracking else { return nil }
        pendingProjectID = projectID
        return resolve(projects: projects)
    }

    mutating func resolve(projects: [Project]) -> Project? {
        guard let pendingProjectID else { return nil }
        guard let project = projects.first(where: { $0.persistentModelID == pendingProjectID }) else {
            return nil
        }
        self.pendingProjectID = nil
        return project
    }

    func shouldAutoStartTracking(hasCreatedProject: Bool, existingProjectCount: Int) -> Bool {
        !hasCreatedProject && existingProjectCount == 0
    }
}
