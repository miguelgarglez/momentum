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
        let focus = Project(name: "Focus", assignedApps: [], assignedDomains: ["notion.so"])
        let safari = Project(name: "Safari", assignedApps: ["com.apple.Safari"], assignedDomains: [])
        container.mainContext.insert(focus)
        container.mainContext.insert(safari)

        let resolver = ProjectAssignmentResolver(modelContainer: container)
        let domainMatch = resolver.resolveProject(for: "com.apple.Safari", domain: "notion.so/wiki/page")
        #expect(domainMatch === focus)
        let bundleMatch = resolver.resolveProject(for: "com.apple.Safari", domain: nil)
        #expect(bundleMatch === safari)
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
        let resolver = ProjectAssignmentResolver(modelContainer: container)
        let result = resolver.resolveProject(for: "com.unknown.app", domain: "unknown.site")
        #expect(result == nil)
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
