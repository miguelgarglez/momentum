import Foundation
import SwiftData

@MainActor
enum SeedData {
    static func seedPendingConflicts(in container: ModelContainer) {
        let context = container.mainContext
        let existingPending = (try? context.fetch(FetchDescriptor<PendingTrackingSession>())) ?? []
        let existingProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard existingPending.isEmpty, existingProjects.isEmpty else { return }

        let bundleID = "com.momentum.seed.app"
        let domain = "example.com"
        let projectA = Project(name: "Momentum Seed A", assignedApps: [bundleID], assignedDomains: [domain])
        let projectB = Project(name: "Momentum Seed B", assignedApps: [bundleID], assignedDomains: [domain])
        context.insert(projectA)
        context.insert(projectB)

        let now = Date()
        let appSession = PendingTrackingSession(
            startDate: now.addingTimeInterval(-180),
            endDate: now,
            appName: "Seed App",
            bundleIdentifier: bundleID,
            domain: nil,
            filePath: nil,
            contextType: AssignmentContextType.app.rawValue,
            contextValue: bundleID,
        )
        let domainSession = PendingTrackingSession(
            startDate: now.addingTimeInterval(-420),
            endDate: now.addingTimeInterval(-120),
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            domain: domain,
            filePath: nil,
            contextType: AssignmentContextType.domain.rawValue,
            contextValue: domain,
        )
        context.insert(appSession)
        context.insert(domainSession)

        try? context.save()
    }

    static func seedAssignmentRules(in container: ModelContainer) {
        let context = container.mainContext
        let existingRules = (try? context.fetch(FetchDescriptor<AssignmentRule>())) ?? []
        guard existingRules.isEmpty else { return }

        let bundleID = "com.momentum.seed.app"
        let project = Project(name: "Regla Seed", assignedApps: [bundleID])
        context.insert(project)

        let referenceDate = Date().addingTimeInterval(-60 * 60 * 24 * 5)
        let rule = AssignmentRule(
            contextType: AssignmentContextType.app.rawValue,
            contextValue: bundleID,
            project: project,
            createdAt: referenceDate,
            lastUsedAt: referenceDate,
        )
        context.insert(rule)

        try? context.save()
    }

    #if DEBUG
        static func seedDebugDataIfNeeded(in container: ModelContainer) {
            let defaults = UserDefaults.standard
            let seedKey = "Momentum.DebugSeeded"
            guard !defaults.bool(forKey: seedKey) else { return }

            let context = container.mainContext
            let existingProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            guard existingProjects.isEmpty else { return }

            let now = Date()
            let calendar = Calendar.current

            func day(_ offset: Int) -> Date {
                calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: now) ?? now)
            }

            func addSession(
                project: Project,
                dayOffset: Int,
                startHour: Int,
                durationMinutes: Int,
                appName: String,
                bundleID: String,
                domain: String? = nil,
            ) {
                guard let start = calendar.date(byAdding: .hour, value: startHour, to: day(dayOffset)) else { return }
                let session = TrackingSession(
                    startDate: start,
                    endDate: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
                    appName: appName,
                    bundleIdentifier: bundleID,
                    domain: domain,
                    filePath: nil,
                    project: project,
                )
                context.insert(session)
                project.sessions.append(session)
            }

            func addSummary(project: Project, dayOffset: Int, minutes: Int) {
                let summary = DailySummary(date: day(dayOffset), seconds: TimeInterval(minutes * 60), project: project)
                context.insert(summary)
                project.dailySummaries.append(summary)
            }

            let deepWork = Project(
                name: "Deep Work",
                assignedApps: ["com.apple.dt.Xcode"],
                assignedDomains: ["developer.apple.com"],
            )
            let writing = Project(
                name: "Writing",
                assignedApps: ["com.apple.iWork.Pages"],
                assignedDomains: ["docs.google.com"],
            )
            let admin = Project(
                name: "Admin",
                assignedApps: ["com.apple.Mail", "com.apple.Calendar"],
                assignedDomains: [],
            )

            let conflictBundle = "com.microsoft.VSCode"
            let conflictDomain = "docs.seed.local"
            let courseA = Project(name: "Curso A", assignedApps: [conflictBundle], assignedDomains: [conflictDomain])
            let courseB = Project(name: "Curso B", assignedApps: [conflictBundle], assignedDomains: [conflictDomain])

            [deepWork, writing, admin, courseA, courseB].forEach { context.insert($0) }

            func addDailySeries(
                project: Project,
                days: Int,
                minutesPattern: [Int],
                startHour: Int,
                appName: String,
                bundleID: String,
                domain: String? = nil,
            ) {
                guard !minutesPattern.isEmpty else { return }
                for dayOffset in 0 ..< days {
                    let minutes = minutesPattern[dayOffset % minutesPattern.count]
                    addSession(
                        project: project,
                        dayOffset: dayOffset,
                        startHour: startHour,
                        durationMinutes: minutes,
                        appName: appName,
                        bundleID: bundleID,
                        domain: domain,
                    )
                    addSummary(project: project, dayOffset: dayOffset, minutes: minutes)
                }
            }

            // Deep Work: ~100h total across 80 days.
            addDailySeries(
                project: deepWork,
                days: 80,
                minutesPattern: [60, 90, 75, 120, 45, 60, 90, 60],
                startHour: 9,
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
            )

            // Writing: heavier total volume across 120 days.
            addDailySeries(
                project: writing,
                days: 120,
                minutesPattern: [60, 120, 90, 90, 120, 60, 90, 90],
                startHour: 14,
                appName: "Pages",
                bundleID: "com.apple.iWork.Pages",
                domain: "docs.google.com",
            )

            // Admin: lower volume across 40 days.
            addDailySeries(
                project: admin,
                days: 40,
                minutesPattern: [30, 45, 15, 20, 30, 40, 25, 35],
                startHour: 17,
                appName: "Mail",
                bundleID: "com.apple.Mail",
            )

            // Conflict projects: much lower volume for variety.
            addDailySeries(
                project: courseA,
                days: 10,
                minutesPattern: [20, 25, 15, 30, 10],
                startHour: 16,
                appName: "VSCode",
                bundleID: conflictBundle,
            )
            addDailySeries(
                project: courseB,
                days: 6,
                minutesPattern: [15, 10, 20],
                startHour: 18,
                appName: "VSCode",
                bundleID: conflictBundle,
            )

            let pendingAppConflict = PendingTrackingSession(
                startDate: now.addingTimeInterval(-900),
                endDate: now.addingTimeInterval(-600),
                appName: "VSCode",
                bundleIdentifier: conflictBundle,
                domain: nil,
                filePath: nil,
                contextType: AssignmentContextType.app.rawValue,
                contextValue: conflictBundle,
            )
            let pendingDomainConflict = PendingTrackingSession(
                startDate: now.addingTimeInterval(-1800),
                endDate: now.addingTimeInterval(-1200),
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                domain: conflictDomain,
                filePath: nil,
                contextType: AssignmentContextType.domain.rawValue,
                contextValue: conflictDomain,
            )
            context.insert(pendingAppConflict)
            context.insert(pendingDomainConflict)

            let ruleDate = now.addingTimeInterval(-60 * 60 * 24 * 7)
            let rule = AssignmentRule(
                contextType: AssignmentContextType.app.rawValue,
                contextValue: "com.apple.dt.Xcode",
                project: deepWork,
                createdAt: ruleDate,
                lastUsedAt: ruleDate,
            )
            context.insert(rule)

            try? context.save()
            defaults.set(true, forKey: seedKey)
        }
    #endif
}
