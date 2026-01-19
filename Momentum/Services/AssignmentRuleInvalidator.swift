import Foundation
import SwiftData

@MainActor
struct AssignmentRuleInvalidator {
    let modelContext: ModelContext

    func invalidateRules(
        for contexts: [AssignmentContext],
        createPendingConflicts: Bool = true,
    ) {
        guard !contexts.isEmpty else { return }
        let uniqueContexts = Dictionary(uniqueKeysWithValues: contexts.map {
            ("\($0.type.rawValue)|\($0.value)", $0)
        }).values
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        for context in uniqueContexts {
            let typeValue = context.type.rawValue
            let contextValue = context.value
            let descriptor = FetchDescriptor<AssignmentRule>(
                predicate: #Predicate {
                    $0.contextType == typeValue &&
                        $0.contextValue == contextValue
                },
            )
            let rules = (try? modelContext.fetch(descriptor)) ?? []
            rules.forEach(modelContext.delete)

            guard createPendingConflicts else { continue }
            guard matchingProjectsCount(for: context, in: projects) > 1 else { continue }
            guard !hasPendingConflict(for: context) else { continue }
            modelContext.insert(makePendingConflict(for: context))
        }
    }

    static func contextsForNewProject(
        apps: [String],
        domains: [String],
        files: [String],
    ) -> [AssignmentContext] {
        assignmentRuleContexts(
            apps: normalizedSet(apps, normalizer: normalizeAppIdentifier),
            domains: normalizedSet(domains, normalizer: normalizeDomain),
            files: normalizedSet(files, normalizer: normalizeFilePath),
        )
    }

    static func contextsForUpdatedProject(
        apps: [String],
        domains: [String],
        files: [String],
        previousApps: [String],
        previousDomains: [String],
        previousFiles: [String],
    ) -> [AssignmentContext] {
        let addedApps = normalizedSet(apps, normalizer: normalizeAppIdentifier)
            .subtracting(normalizedSet(previousApps, normalizer: normalizeAppIdentifier))
        let addedDomains = normalizedSet(domains, normalizer: normalizeDomain)
            .subtracting(normalizedSet(previousDomains, normalizer: normalizeDomain))
        let addedFiles = normalizedSet(files, normalizer: normalizeFilePath)
            .subtracting(normalizedSet(previousFiles, normalizer: normalizeFilePath))
        return assignmentRuleContexts(apps: addedApps, domains: addedDomains, files: addedFiles)
    }

    static func contextsForRemovedProject(
        apps: [String],
        domains: [String],
        files: [String],
        previousApps: [String],
        previousDomains: [String],
        previousFiles: [String],
    ) -> [AssignmentContext] {
        let removedApps = normalizedSet(previousApps, normalizer: normalizeAppIdentifier)
            .subtracting(normalizedSet(apps, normalizer: normalizeAppIdentifier))
        let removedDomains = normalizedSet(previousDomains, normalizer: normalizeDomain)
            .subtracting(normalizedSet(domains, normalizer: normalizeDomain))
        let removedFiles = normalizedSet(previousFiles, normalizer: normalizeFilePath)
            .subtracting(normalizedSet(files, normalizer: normalizeFilePath))
        return assignmentRuleContexts(apps: removedApps, domains: removedDomains, files: removedFiles)
    }

    private static func assignmentRuleContexts(
        apps: Set<String>,
        domains: Set<String>,
        files: Set<String>,
    ) -> [AssignmentContext] {
        var contexts: [AssignmentContext] = []
        contexts.reserveCapacity(apps.count + domains.count + files.count)
        contexts.append(contentsOf: apps.map { AssignmentContext(type: .app, value: $0) })
        contexts.append(contentsOf: domains.map { AssignmentContext(type: .domain, value: $0) })
        contexts.append(contentsOf: files.map { AssignmentContext(type: .file, value: $0) })
        return contexts
    }

    private static func normalizedSet(
        _ values: [String],
        normalizer: (String) -> String?,
    ) -> Set<String> {
        Set(values.compactMap(normalizer))
    }

    private static func normalizeAppIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeDomain(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return lowered.isEmpty ? nil : lowered
    }

    private static func normalizeFilePath(_ value: String) -> String? {
        let normalized = value.normalizedFilePath
        return normalized.isEmpty ? nil : normalized
    }
}

private extension AssignmentRuleInvalidator {
    func matchingProjectsCount(for context: AssignmentContext, in projects: [Project]) -> Int {
        switch context.type {
        case .app:
            return projects.filter { $0.matches(appBundleIdentifier: context.value) }.count
        case .domain:
            return projects.filter { $0.matches(domain: context.value) }.count
        case .file:
            return projects.filter { $0.matches(filePath: context.value) }.count
        }
    }

    func hasPendingConflict(for context: AssignmentContext) -> Bool {
        let typeValue = context.type.rawValue
        let contextValue = context.value
        let descriptor = FetchDescriptor<PendingTrackingSession>(
            predicate: #Predicate {
                $0.contextType == typeValue &&
                    $0.contextValue == contextValue
            },
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
    }

    func makePendingConflict(for context: AssignmentContext) -> PendingTrackingSession {
        let now = Date()
        if let latest = latestSessionDetails(for: context) {
            return PendingTrackingSession(
                startDate: now,
                endDate: now,
                appName: latest.appName,
                bundleIdentifier: latest.bundleIdentifier,
                domain: latest.domain,
                filePath: latest.filePath,
                contextType: context.type.rawValue,
                contextValue: context.value,
            )
        }
        return PendingTrackingSession(
            startDate: now,
            endDate: now,
            appName: fallbackAppName(for: context),
            bundleIdentifier: context.type == .app ? context.value : nil,
            domain: context.type == .domain ? context.value : nil,
            filePath: context.type == .file ? context.value : nil,
            contextType: context.type.rawValue,
            contextValue: context.value,
        )
    }

    func latestSessionDetails(for context: AssignmentContext) -> (
        appName: String,
        bundleIdentifier: String?,
        domain: String?,
        filePath: String?
    )? {
        var descriptor = FetchDescriptor<TrackingSession>(
            sortBy: [SortDescriptor(\.endDate, order: .reverse)],
        )
        descriptor.fetchLimit = 50
        guard let sessions = try? modelContext.fetch(descriptor) else { return nil }
        for session in sessions {
            if sessionMatchesContext(session, context: context) {
                return (
                    appName: session.appName,
                    bundleIdentifier: session.bundleIdentifier,
                    domain: session.domain,
                    filePath: session.filePath
                )
            }
        }
        return nil
    }

    func sessionMatchesContext(_ session: TrackingSession, context: AssignmentContext) -> Bool {
        switch context.type {
        case .app:
            guard let bundleIdentifier = session.bundleIdentifier else { return false }
            return bundleIdentifier.caseInsensitiveCompare(context.value) == .orderedSame
        case .domain:
            guard let domain = session.domain?.lowercased() else { return false }
            return domain.contains(context.value)
        case .file:
            guard let filePath = session.filePath else { return false }
            return filePath.normalizedFilePath.caseInsensitiveCompare(context.value) == .orderedSame
        }
    }

    func fallbackAppName(for context: AssignmentContext) -> String {
        switch context.type {
        case .app:
            return context.value
        case .domain:
            return "Dominio en conflicto"
        case .file:
            return "Archivo en conflicto"
        }
    }
}
