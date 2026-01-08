import Foundation
import SwiftData
import Testing
@testable import Momentum

@MainActor
struct MomentumTests {
    private let factory = InMemoryModelContainerFactory()

    @Test("Resolver prioriza dominios sobre bundles")
    func projectAssignmentPrefersDomains() throws {
        let container = try factory.makeContainer()
        let settings = makeSettings()
        let focus = Project(name: "Focus", assignedApps: [], assignedDomains: ["notion.so"])
        let safari = Project(name: "Safari", assignedApps: ["com.apple.Safari"], assignedDomains: [])
        container.mainContext.insert(focus)
        container.mainContext.insert(safari)

        let resolver = ProjectAssignmentResolver(modelContainer: container, settings: settings)
        let domainMatch = resolver.resolveProject(for: "com.apple.Safari", domain: "notion.so/wiki/page")
        #expect(domainMatch === focus)
        let bundleMatch = resolver.resolveProject(for: "com.apple.Safari", domain: nil)
        #expect(bundleMatch === safari)
    }

    @Test("Resolver ignora el bundle si el dominio no coincide")
    func projectAssignmentRequiresDomainMatchWhenProvided() throws {
        let container = try factory.makeContainer()
        let settings = makeSettings()
        let browsing = Project(name: "Browsing", assignedApps: ["com.apple.Safari"], assignedDomains: ["docs.test"])
        container.mainContext.insert(browsing)
        let resolver = ProjectAssignmentResolver(modelContainer: container, settings: settings)
        let noMatch = resolver.resolveProject(for: "com.apple.Safari", domain: "medium.com")
        #expect(noMatch == nil)
    }

    @Test("Cálculo de racha corta en cuanto hay un día vacío")
    func streakStopsWhenThereIsAGap() throws {
        let container = try factory.makeContainer()
        let project = Project(name: "Racha")
        container.mainContext.insert(project)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func session(start offsetHours: Int, duration: TimeInterval = 1800, dayOffset: Int) {
            guard let start = calendar.date(byAdding: .day, value: dayOffset, to: today)?.addingTimeInterval(TimeInterval(offsetHours) * 3600) else { return }
            let session = TrackingSession(
                startDate: start,
                endDate: start.addingTimeInterval(duration),
                appName: "Xcode",
                bundleIdentifier: "com.test.xcode",
                domain: nil,
                project: project
            )
            container.mainContext.insert(session)
            project.sessions.append(session)
        }

        session(start: 2, dayOffset: 0)
        session(start: 3, dayOffset: -1)
        session(start: 4, dayOffset: -3)
        #expect(project.streakCount == 2)
    }

    @Test("Mejor racha usa todo el historial")
    func longestStreakUsesHistory() throws {
        let container = try factory.makeContainer()
        let project = Project(name: "Mejor racha")
        container.mainContext.insert(project)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func session(dayOffset: Int, startHour: Int = 2, duration: TimeInterval = 1800) {
            guard let start = calendar.date(byAdding: .day, value: dayOffset, to: today)?.addingTimeInterval(TimeInterval(startHour) * 3600) else { return }
            let session = TrackingSession(
                startDate: start,
                endDate: start.addingTimeInterval(duration),
                appName: "Xcode",
                bundleIdentifier: "com.test.xcode",
                domain: nil,
                project: project
            )
            container.mainContext.insert(session)
            project.sessions.append(session)
        }

        session(dayOffset: -1)
        session(dayOffset: -2)
        session(dayOffset: -4)
        session(dayOffset: -5)

        #expect(project.longestStreakCount == 2)
        #expect(project.streakCount == 0)
    }

    @Test("Mejor racha considera los daily summaries")
    func longestStreakUsesDailySummaries() throws {
        let container = try factory.makeContainer()
        let project = Project(name: "Resúmenes racha")
        container.mainContext.insert(project)
        let calendar = Calendar.current

        for offset in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { continue }
            let summary = DailySummary(date: day, seconds: 600, project: project)
            container.mainContext.insert(summary)
            project.dailySummaries.append(summary)
        }

        #expect(project.longestStreakCount == 3)
    }

    @Test("Agregación semanal usa DailySummary cache cuando existe")
    func weeklyAggregationUsesDailySummaries() throws {
        let container = try factory.makeContainer()
        let project = Project(name: "Resúmenes")
        container.mainContext.insert(project)
        let calendar = Calendar.current
        for offset in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { continue }
            let summary = DailySummary(date: day, seconds: TimeInterval(600 * (offset + 1)), project: project)
            container.mainContext.insert(summary)
            project.dailySummaries.append(summary)
        }
        #expect(project.weeklySeconds == 3600)
    }

    @Test("Resolver devuelve nil cuando no hay coincidencias")
    func projectAssignmentReturnsNilWhenNoMatch() throws {
        let container = try factory.makeContainer()
        let resolver = ProjectAssignmentResolver(modelContainer: container, settings: makeSettings())
        let result = resolver.resolveProject(for: "com.unknown.app", domain: "unknown.site")
        #expect(result == nil)
    }

    @Test("Resolver detecta conflicto cuando hay multiples proyectos")
    func projectAssignmentDetectsConflicts() throws {
        let container = try factory.makeContainer()
        let settings = makeSettings()
        let bundleID = "com.test.vscode"
        let projectA = Project(name: "Dev", assignedApps: [bundleID])
        let projectB = Project(name: "Curso", assignedApps: [bundleID])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)

        let resolver = ProjectAssignmentResolver(modelContainer: container, settings: settings)
        let result = resolver.resolveAssignment(for: bundleID, domain: nil)
        switch result {
        case let .conflict(context, candidates):
            #expect(context.type == .app)
            #expect(context.value == bundleID)
            #expect(candidates.count == 2)
        default:
            #expect(Bool(false), "Expected conflict result")
        }
    }

    @Test("Resolver usa regla guardada para resolver conflicto")
    func projectAssignmentUsesRules() throws {
        let container = try factory.makeContainer()
        let settings = makeSettings()
        let bundleID = "com.test.vscode"
        let projectA = Project(name: "Dev", assignedApps: [bundleID])
        let projectB = Project(name: "Curso", assignedApps: [bundleID])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)
        let rule = AssignmentRule(
            contextType: AssignmentContextType.app.rawValue,
            contextValue: bundleID,
            project: projectB
        )
        container.mainContext.insert(rule)

        let resolver = ProjectAssignmentResolver(modelContainer: container, settings: settings)
        let result = resolver.resolveAssignment(for: bundleID, domain: nil)
        switch result {
        case let .assigned(project, usedRule):
            #expect(usedRule)
            #expect(project === projectB)
        default:
            #expect(Bool(false), "Expected assignment via rule")
        }
    }

    @Test("Resolver ignora reglas expiradas")
    func projectAssignmentSkipsExpiredRules() throws {
        let container = try factory.makeContainer()
        let bundleID = "com.test.vscode"
        let projectA = Project(name: "Dev", assignedApps: [bundleID])
        let projectB = Project(name: "Curso", assignedApps: [bundleID])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)

        let settings = makeSettings()
        settings.assignmentRuleExpiration = .days30

        let expiredDate = Date().addingTimeInterval(-60 * 60 * 24 * 40)
        let rule = AssignmentRule(
            contextType: AssignmentContextType.app.rawValue,
            contextValue: bundleID,
            project: projectB,
            createdAt: expiredDate,
            lastUsedAt: expiredDate
        )
        container.mainContext.insert(rule)

        let resolver = ProjectAssignmentResolver(modelContainer: container, settings: settings)
        let result = resolver.resolveAssignment(for: bundleID, domain: nil)
        switch result {
        case let .conflict(context, candidates):
            #expect(context.type == .app)
            #expect(context.value == bundleID)
            #expect(candidates.count == 2)
        default:
            #expect(Bool(false), "Expected conflict when rule is expired")
        }

        let remainingRules = try container.mainContext.fetch(FetchDescriptor<AssignmentRule>())
        #expect(remainingRules.isEmpty)
    }

    private func makeSettings() -> TrackerSettings {
        let suiteName = "MomentumTests.Settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return TrackerSettings(defaults: defaults)
    }

    @Test("Resolver de solapamientos recorta y divide sesiones")
    func overlapResolverSplitsSessions() throws {
        let container = try factory.makeContainer()
        let project = Project(name: "Solapamientos")
        container.mainContext.insert(project)
        let base = Date()
        let first = TrackingSession(
            startDate: base,
            endDate: base.addingTimeInterval(3600),
            appName: "Xcode",
            bundleIdentifier: "com.test.xcode",
            domain: nil,
            project: project
        )
        let second = TrackingSession(
            startDate: base.addingTimeInterval(3600),
            endDate: base.addingTimeInterval(7200),
            appName: "Safari",
            bundleIdentifier: "com.test.safari",
            domain: nil,
            project: project
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)

        let resolver = SessionOverlapResolver(context: container.mainContext)
        let interval = DateInterval(start: base.addingTimeInterval(900), end: base.addingTimeInterval(4500))
        let removed = resolver.resolveOverlaps(with: interval)
        #expect(removed.count == 2)
        #expect(first.endDate == base.addingTimeInterval(900))
        #expect(second.startDate == base.addingTimeInterval(4500))

        let third = TrackingSession(
            startDate: base.addingTimeInterval(7200),
            endDate: base.addingTimeInterval(9000),
            appName: "Pages",
            bundleIdentifier: "com.test.pages",
            domain: nil,
            project: project
        )
        container.mainContext.insert(third)
        let originalThirdEnd = third.endDate
        let splitInterval = DateInterval(start: base.addingTimeInterval(7800), end: base.addingTimeInterval(8100))
        _ = resolver.resolveOverlaps(with: splitInterval)
        try container.mainContext.save()
        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(sessions.contains {
            abs($0.startDate.timeIntervalSince(base.addingTimeInterval(8100))) < 1 &&
            abs($0.endDate.timeIntervalSince(originalThirdEnd)) < 1
        })
    }

    @Test("Tracking activo/idle actualiza el summary")
    func activityTrackerReflectsIdleState() throws {
        let scenario = try factory.makeTrackerScenario()
        scenario.tracker.testing_beginContext(appName: "Xcode", bundleIdentifier: scenario.primaryBundle, startDate: Date().addingTimeInterval(-40))
        #expect(scenario.tracker.statusSummary.state == .tracking)
        scenario.tracker.testing_forceIdleState(true)
        #expect(scenario.tracker.statusSummary.state == .pausedIdle)
        scenario.tracker.testing_forceIdleState(false)
        #expect(scenario.tracker.statusSummary.state == .tracking)
    }

    @Test("Cambios rápidos de apps generan sesiones sin solape")
    func activityTrackerHandlesRapidAppSwitches() throws {
        let scenario = try factory.makeTrackerScenario()
        scenario.tracker.testing_beginContext(appName: "Xcode", bundleIdentifier: scenario.primaryBundle, startDate: Date().addingTimeInterval(-120))
        scenario.tracker.testing_beginContext(appName: "Safari", bundleIdentifier: scenario.secondaryBundle, startDate: Date().addingTimeInterval(-50))
        let initialSessions = try scenario.container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(initialSessions.count == 1)
        #expect(initialSessions.first?.bundleIdentifier == scenario.primaryBundle)
        #expect(initialSessions.first?.duration ?? 0 > 60)
        #expect(scenario.tracker.testing_forceFlush())
        let finalSessions = try scenario.container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(finalSessions.count == 2)
    }

    @Test("Si no hay dominio, la asignación cae al bundle")
    func activityTrackerFallsBackToBundleWhenDomainMissing() throws {
        let scenario = try factory.makeTrackerScenario()
        scenario.tracker.testing_beginContext(appName: "Focus", bundleIdentifier: scenario.primaryBundle, domain: nil, startDate: Date().addingTimeInterval(-20))
        #expect(scenario.tracker.statusSummary.projectName == scenario.primaryProject.name)
    }

    @Test("Tracker descarta sesiones sin proyecto asociado")
    func activityTrackerSkipsUnassignedApps() throws {
        let container = try factory.makeContainer()
        let suiteName = "MomentumTests.Unassigned.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )
        tracker.testing_beginContext(appName: "Momentum", bundleIdentifier: "run.momentum.app", startDate: Date().addingTimeInterval(-120))
        #expect(tracker.testing_forceFlush())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(sessions.isEmpty)
    }

    @Test("Tracker descarta dominios sin asignar aunque la app coincida")
    func activityTrackerSkipsSessionsWhenDomainUnassigned() throws {
        let scenario = try factory.makeTrackerScenario()
        scenario.tracker.testing_beginContext(
            appName: "Safari",
            bundleIdentifier: scenario.secondaryBundle,
            domain: "unknown.com",
            startDate: Date().addingTimeInterval(-60)
        )
        #expect(scenario.tracker.statusSummary.projectName == nil)
        #expect(scenario.tracker.testing_forceFlush())
        let sessions = try scenario.container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(sessions.isEmpty)
    }

    @Test("Tracker guarda sesiones pendientes cuando hay conflicto")
    func activityTrackerStoresPendingOnConflict() throws {
        let container = try factory.makeContainer()
        let bundleID = "com.test.vscode"
        let projectA = Project(name: "Dev", assignedApps: [bundleID])
        let projectB = Project(name: "Curso", assignedApps: [bundleID])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)
        let suiteName = "MomentumTests.Pending.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        tracker.testing_beginContext(
            appName: "VSCode",
            bundleIdentifier: bundleID,
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())

        let pending = try container.mainContext.fetch(FetchDescriptor<PendingTrackingSession>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(pending.count == 1)
        #expect(sessions.isEmpty)
    }

    @Test("Resolver conflicto crea regla y vuelca pendientes")
    func activityTrackerResolvesPendingSessions() throws {
        let container = try factory.makeContainer()
        let bundleID = "com.test.vscode"
        let projectA = Project(name: "Dev", assignedApps: [bundleID])
        let projectB = Project(name: "Curso", assignedApps: [bundleID])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)
        let suiteName = "MomentumTests.Resolve.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        let pending = PendingTrackingSession(
            startDate: Date().addingTimeInterval(-120),
            endDate: Date().addingTimeInterval(-60),
            appName: "VSCode",
            bundleIdentifier: bundleID,
            domain: nil,
            contextType: AssignmentContextType.app.rawValue,
            contextValue: bundleID
        )
        container.mainContext.insert(pending)
        try container.mainContext.save()

        tracker.resolveConflict(
            context: AssignmentContext(type: .app, value: bundleID),
            project: projectB
        )

        let rules = try container.mainContext.fetch(FetchDescriptor<AssignmentRule>())
        let remainingPending = try container.mainContext.fetch(FetchDescriptor<PendingTrackingSession>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(rules.count == 1)
        #expect(rules.first?.project === projectB)
        #expect(remainingPending.isEmpty)
        #expect(sessions.count == 1)
        #expect(sessions.first?.project === projectB)
        #expect(tracker.pendingConflictCount == 0)
    }

    @Test("Regla evita volver a crear pendientes")
    func activityTrackerUsesRuleAfterResolution() throws {
        let container = try factory.makeContainer()
        let bundleID = "com.test.vscode"
        let projectA = Project(name: "Dev", assignedApps: [bundleID])
        let projectB = Project(name: "Curso", assignedApps: [bundleID])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)
        let suiteName = "MomentumTests.Rule.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        tracker.resolveConflict(
            context: AssignmentContext(type: .app, value: bundleID),
            project: projectA
        )

        tracker.testing_beginContext(
            appName: "VSCode",
            bundleIdentifier: bundleID,
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())

        let pending = try container.mainContext.fetch(FetchDescriptor<PendingTrackingSession>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(pending.isEmpty)
        #expect(sessions.count == 1)
        #expect(sessions.first?.project === projectA)
    }

    @Test("Conflicto por dominio crea pendientes")
    func activityTrackerStoresPendingOnDomainConflict() throws {
        let container = try factory.makeContainer()
        let domain = "docs.test"
        let projectA = Project(name: "DocA", assignedApps: [], assignedDomains: [domain])
        let projectB = Project(name: "DocB", assignedApps: [], assignedDomains: [domain])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)
        let suiteName = "MomentumTests.DomainPending.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        tracker.testing_beginContext(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            domain: domain,
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())

        let pending = try container.mainContext.fetch(FetchDescriptor<PendingTrackingSession>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(pending.count == 1)
        #expect(sessions.isEmpty)
    }

    @Test("No se crea pendiente cuando hay un unico proyecto")
    func activityTrackerDoesNotCreatePendingWhenSingleMatch() throws {
        let container = try factory.makeContainer()
        let bundleID = "com.test.vscode"
        let project = Project(name: "Dev", assignedApps: [bundleID])
        container.mainContext.insert(project)
        let suiteName = "MomentumTests.NoPending.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        tracker.testing_beginContext(
            appName: "VSCode",
            bundleIdentifier: bundleID,
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())

        let pending = try container.mainContext.fetch(FetchDescriptor<PendingTrackingSession>())
        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        #expect(pending.isEmpty)
        #expect(sessions.count == 1)
    }

    @Test("Tracking manual guarda sesiones en el proyecto manual")
    func activityTrackerManualTrackingPersistsToManualProject() throws {
        let container = try factory.makeContainer()
        let settings = makeSettings()
        let manualProject = Project(name: "Manual")
        container.mainContext.insert(manualProject)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        tracker.testing_startManualTracking(project: manualProject)
        tracker.testing_beginContext(
            appName: "Xcode",
            bundleIdentifier: "com.test.xcode",
            domain: "docs.test",
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())

        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        let pending = try container.mainContext.fetch(FetchDescriptor<PendingTrackingSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.project === manualProject)
        #expect(pending.isEmpty)
        #expect(manualProject.assignedApps.contains { $0 == "com.test.xcode" })
        #expect(manualProject.assignedDomains.contains { $0 == "docs.test" })
    }

    @Test("Tracking manual ignora conflictos de asignación")
    func activityTrackerManualTrackingSkipsConflicts() throws {
        let container = try factory.makeContainer()
        let settings = makeSettings()
        let bundleID = "com.test.conflict"
        let manualProject = Project(name: "Manual")
        let projectA = Project(name: "A", assignedApps: [bundleID])
        let projectB = Project(name: "B", assignedApps: [bundleID])
        container.mainContext.insert(manualProject)
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        tracker.testing_startManualTracking(project: manualProject)
        tracker.testing_beginContext(
            appName: "VSCode",
            bundleIdentifier: bundleID,
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())

        let sessions = try container.mainContext.fetch(FetchDescriptor<TrackingSession>())
        let pending = try container.mainContext.fetch(FetchDescriptor<PendingTrackingSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.project === manualProject)
        #expect(pending.isEmpty)
    }

    @Test("Tracking manual no agrega dominios si la opción está desactivada")
    func activityTrackerManualTrackingSkipsDomainWhenDisabled() throws {
        let container = try factory.makeContainer()
        let settings = makeSettings()
        settings.isDomainTrackingEnabled = false
        let manualProject = Project(name: "Manual")
        container.mainContext.insert(manualProject)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        tracker.testing_startManualTracking(project: manualProject)
        tracker.testing_beginContext(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            domain: "example.com",
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())

        #expect(manualProject.assignedDomains.isEmpty)
    }

    @Test("El contador de pendientes refleja inserciones")
    func activityTrackerPendingCountIncrements() throws {
        let container = try factory.makeContainer()
        let bundleID = "com.test.vscode"
        let projectA = Project(name: "Dev", assignedApps: [bundleID])
        let projectB = Project(name: "Curso", assignedApps: [bundleID])
        container.mainContext.insert(projectA)
        container.mainContext.insert(projectB)
        let suiteName = "MomentumTests.PendingCount.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )

        #expect(tracker.pendingConflictCount == 0)
        tracker.testing_beginContext(
            appName: "VSCode",
            bundleIdentifier: bundleID,
            startDate: Date().addingTimeInterval(-40)
        )
        #expect(tracker.testing_forceFlush())
        #expect(tracker.pendingConflictCount == 1)
    }
}

@MainActor
final class InMemoryModelContainerFactory {
    struct TrackerScenario {
        let tracker: ActivityTracker
        let container: ModelContainer
        let primaryProject: Project
        let primaryBundle: String
        let secondaryBundle: String
    }

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            AssignmentRule.self,
            PendingTrackingSession.self,
            TrackingSession.self,
            DailySummary.self
        ])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func makeTrackerScenario() throws -> TrackerScenario {
        let container = try makeContainer()
        let primaryBundle = "com.test.xcode"
        let secondaryBundle = "com.test.safari"
        let project = Project(name: "Builder", assignedApps: [primaryBundle], assignedDomains: [])
        let secondary = Project(name: "Browsing", assignedApps: [secondaryBundle], assignedDomains: ["docs.test"])
        container.mainContext.insert(project)
        container.mainContext.insert(secondary)
        let suiteName = "MomentumTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite for tests")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TrackerSettings(defaults: defaults)
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: settings,
            crashRecovery: MockCrashRecoveryHandler(),
            performanceMonitor: MockPerformanceMonitor()
        )
        return TrackerScenario(tracker: tracker, container: container, primaryProject: project, primaryBundle: primaryBundle, secondaryBundle: secondaryBundle)
    }
}

@MainActor
final class MockCrashRecoveryHandler: CrashRecoveryHandling {
    var persistedSnapshot: SessionSnapshot?

    func persist(snapshot: SessionSnapshot?) {
        persistedSnapshot = snapshot
    }

    func consumePendingSnapshot() -> SessionSnapshot? {
        let snapshot = persistedSnapshot
        persistedSnapshot = nil
        return snapshot
    }
}

@MainActor
final class MockPerformanceMonitor: PerformanceBudgetMonitoring {
    @discardableResult
    func measure<T>(_ operation: String, work: () throws -> T) rethrows -> T {
        try work()
    }

    func recordSample(_ sample: PerformanceBudgetMonitor.MetricSample) {
        // no-op for tests
    }
}
