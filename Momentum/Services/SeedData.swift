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

        static func seedPortfolioScreenshotDataIfNeeded(in container: ModelContainer) {
            let context = container.mainContext
            let existingProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            let existingSessions = (try? context.fetch(FetchDescriptor<TrackingSession>())) ?? []
            let existingPending = (try? context.fetch(FetchDescriptor<PendingTrackingSession>())) ?? []
            guard existingProjects.isEmpty, existingSessions.isEmpty, existingPending.isEmpty else { return }

            struct PortfolioSessionContext {
                let appName: String
                let bundleIdentifier: String?
                let domain: String?
                let filePath: String?
                let source: TrackingSessionSource
            }

            struct PortfolioProjectSpec {
                let name: String
                let colorHex: String
                let iconName: String
                let assignedApps: [String]
                let assignedDomains: [String]
                let activeDays: Int
                let startHour: Int
                let minutePattern: [Int]
                let weekendMultiplier: Double
                let seedOffset: Int
                let contexts: [PortfolioSessionContext]
            }

            let now = Date()
            let calendar = Calendar.current

            func startOfDay(dayOffset: Int) -> Date {
                let raw = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
                return calendar.startOfDay(for: raw)
            }

            func deterministicJitter(dayOffset: Int, seed: Int, maxValue: Int) -> Int {
                guard maxValue > 0 else { return 0 }
                return abs((dayOffset * 37) + (seed * 19) + 11) % maxValue
            }

            let specs: [PortfolioProjectSpec] = [
                PortfolioProjectSpec(
                    name: "Deep Focus",
                    colorHex: "#FE7A71",
                    iconName: "brain",
                    assignedApps: ["com.apple.dt.Xcode", "com.microsoft.VSCode"],
                    assignedDomains: ["github.com", "developer.apple.com", "linear.app"],
                    activeDays: 90,
                    startHour: 9,
                    minutePattern: [180, 210, 0, 170, 220, 120, 0, 195, 160, 0, 200, 150, 110, 0],
                    weekendMultiplier: 0.45,
                    seedOffset: 1,
                    contexts: [
                        PortfolioSessionContext(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", domain: "developer.apple.com", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", domain: "github.com", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", domain: "linear.app", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "Product Build",
                    colorHex: "#FFB347",
                    iconName: "hammer",
                    assignedApps: ["com.apple.dt.Xcode", "com.apple.Terminal", "com.microsoft.VSCode"],
                    assignedDomains: ["github.com", "linear.app", "vercel.com"],
                    activeDays: 90,
                    startHour: 11,
                    minutePattern: [120, 100, 70, 135, 0, 90, 0, 140, 110, 80, 125, 0, 95, 65],
                    weekendMultiplier: 0.40,
                    seedOffset: 2,
                    contexts: [
                        PortfolioSessionContext(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", domain: "github.com", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", domain: nil, filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", domain: "linear.app", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "Client Work",
                    colorHex: "#1F9D55",
                    iconName: "briefcase",
                    assignedApps: ["com.microsoft.VSCode", "com.google.Chrome", "com.tinyspeck.slackmacgap"],
                    assignedDomains: ["notion.so", "linear.app", "slack.com"],
                    activeDays: 90,
                    startHour: 13,
                    minutePattern: [110, 140, 95, 75, 0, 100, 0, 130, 85, 105, 60, 0, 95, 120],
                    weekendMultiplier: 0.30,
                    seedOffset: 3,
                    contexts: [
                        PortfolioSessionContext(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", domain: "linear.app", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", domain: "notion.so", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", domain: "slack.com", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "UI Design",
                    colorHex: "#009FB7",
                    iconName: "🎨",
                    assignedApps: ["com.figma.Desktop", "com.apple.Safari"],
                    assignedDomains: ["figma.com", "dribbble.com"],
                    activeDays: 72,
                    startHour: 10,
                    minutePattern: [85, 120, 0, 95, 110, 70, 0, 90, 130, 0, 80, 105, 65, 0],
                    weekendMultiplier: 0.50,
                    seedOffset: 4,
                    contexts: [
                        PortfolioSessionContext(appName: "Figma", bundleIdentifier: "com.figma.Desktop", domain: "figma.com", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", domain: "dribbble.com", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "Documentation",
                    colorHex: "#5C6AC4",
                    iconName: "pencil",
                    assignedApps: ["com.apple.iWork.Pages", "com.apple.Notes", "com.google.Chrome"],
                    assignedDomains: ["docs.google.com", "notion.so"],
                    activeDays: 84,
                    startHour: 15,
                    minutePattern: [60, 45, 75, 35, 0, 55, 0, 65, 40, 55, 30, 0, 50, 70],
                    weekendMultiplier: 0.35,
                    seedOffset: 5,
                    contexts: [
                        PortfolioSessionContext(appName: "Pages", bundleIdentifier: "com.apple.iWork.Pages", domain: nil, filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", domain: nil, filePath: nil, source: .manualEntry),
                        PortfolioSessionContext(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", domain: "docs.google.com", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "Analytics Review",
                    colorHex: "#A78BFA",
                    iconName: "chart.bar",
                    assignedApps: ["com.apple.Safari", "com.google.Chrome"],
                    assignedDomains: ["analytics.google.com", "mixpanel.com"],
                    activeDays: 65,
                    startHour: 16,
                    minutePattern: [45, 35, 50, 0, 40, 30, 0, 60, 25, 0, 55, 30, 0, 35],
                    weekendMultiplier: 0.25,
                    seedOffset: 6,
                    contexts: [
                        PortfolioSessionContext(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", domain: "analytics.google.com", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", domain: "mixpanel.com", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "Marketing Site",
                    colorHex: "#E879F9",
                    iconName: "paperplane",
                    assignedApps: ["com.microsoft.VSCode", "com.google.Chrome"],
                    assignedDomains: ["vercel.com", "webflow.com"],
                    activeDays: 58,
                    startHour: 14,
                    minutePattern: [55, 70, 0, 65, 85, 45, 0, 60, 90, 0, 75, 50, 0, 55],
                    weekendMultiplier: 0.50,
                    seedOffset: 7,
                    contexts: [
                        PortfolioSessionContext(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", domain: "vercel.com", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", domain: "webflow.com", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "Inbox & Admin",
                    colorHex: "#14B8A6",
                    iconName: "folder",
                    assignedApps: ["com.apple.mail", "com.apple.iCal", "com.tinyspeck.slackmacgap"],
                    assignedDomains: ["mail.google.com", "calendar.google.com", "slack.com"],
                    activeDays: 90,
                    startHour: 17,
                    minutePattern: [35, 25, 40, 20, 0, 30, 15, 0, 25, 20, 35, 10, 0, 30],
                    weekendMultiplier: 0.20,
                    seedOffset: 8,
                    contexts: [
                        PortfolioSessionContext(appName: "Mail", bundleIdentifier: "com.apple.mail", domain: "mail.google.com", filePath: nil, source: .manualEntry),
                        PortfolioSessionContext(appName: "Calendar", bundleIdentifier: "com.apple.iCal", domain: "calendar.google.com", filePath: nil, source: .manualEntry),
                        PortfolioSessionContext(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", domain: "slack.com", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "R&D Experiments",
                    colorHex: "#22C55E",
                    iconName: "🔬",
                    assignedApps: ["com.googlecode.iterm2", "com.apple.Terminal", "com.microsoft.VSCode"],
                    assignedDomains: ["openai.com", "huggingface.co", "stackoverflow.com"],
                    activeDays: 42,
                    startHour: 10,
                    minutePattern: [70, 0, 90, 60, 0, 80, 45, 0, 100, 50, 0, 75, 55, 0],
                    weekendMultiplier: 0.55,
                    seedOffset: 9,
                    contexts: [
                        PortfolioSessionContext(appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", domain: nil, filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", domain: "stackoverflow.com", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", domain: "openai.com", filePath: nil, source: .automatic),
                    ],
                ),
                PortfolioProjectSpec(
                    name: "Bug Triage",
                    colorHex: "#F97316",
                    iconName: "🐞",
                    assignedApps: ["com.microsoft.VSCode", "com.apple.Safari"],
                    assignedDomains: ["sentry.io", "github.com"],
                    activeDays: 50,
                    startHour: 11,
                    minutePattern: [40, 55, 0, 35, 60, 20, 0, 45, 50, 0, 30, 45, 0, 25],
                    weekendMultiplier: 0.25,
                    seedOffset: 10,
                    contexts: [
                        PortfolioSessionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", domain: "sentry.io", filePath: nil, source: .automatic),
                        PortfolioSessionContext(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", domain: "github.com", filePath: nil, source: .automatic),
                    ],
                ),
            ]

            var projectsByName: [String: Project] = [:]
            for spec in specs {
                let project = Project(
                    name: spec.name,
                    colorHex: spec.colorHex,
                    iconName: spec.iconName,
                    assignedApps: spec.assignedApps,
                    assignedDomains: spec.assignedDomains,
                )
                context.insert(project)
                projectsByName[spec.name] = project
            }

            for spec in specs {
                guard let project = projectsByName[spec.name] else { continue }

                for dayOffset in 0 ..< spec.activeDays {
                    let dayDate = startOfDay(dayOffset: dayOffset)
                    let weekday = calendar.component(.weekday, from: dayDate)
                    let isWeekend = weekday == 1 || weekday == 7

                    let baseMinutes = spec.minutePattern[dayOffset % spec.minutePattern.count]
                    guard baseMinutes > 0 else { continue }

                    var adjustedMinutes = isWeekend
                        ? Int(Double(baseMinutes) * spec.weekendMultiplier)
                        : baseMinutes

                    let modulation = deterministicJitter(dayOffset: dayOffset, seed: spec.seedOffset, maxValue: 12)
                    adjustedMinutes += (modulation - 5)

                    // Keep "today" visually partial so metric cards look believable.
                    if dayOffset == 0 {
                        adjustedMinutes = Int(Double(adjustedMinutes) * 0.35)
                    }

                    guard adjustedMinutes >= 10 else { continue }

                    let shouldSplit = adjustedMinutes >= 115
                        && ((dayOffset + spec.seedOffset) % 3 == 0)
                        && spec.contexts.count > 1

                    let segments: [Int]
                    if shouldSplit {
                        let first = Int(Double(adjustedMinutes) * 0.58)
                        let second = adjustedMinutes - first
                        segments = [first, second]
                    } else {
                        segments = [adjustedMinutes]
                    }

                    var dayTotalMinutes = 0
                    for (segmentIndex, segmentMinutes) in segments.enumerated() {
                        guard segmentMinutes > 0 else { continue }

                        let contextIndex = (dayOffset + segmentIndex + spec.seedOffset) % spec.contexts.count
                        let sessionContext = spec.contexts[contextIndex]

                        guard let baseStart = calendar.date(
                            byAdding: .hour,
                            value: spec.startHour + (segmentIndex * 3),
                            to: dayDate,
                        ) else { continue }

                        let startMinute = deterministicJitter(
                            dayOffset: dayOffset + (segmentIndex * 2),
                            seed: spec.seedOffset,
                            maxValue: 45,
                        )
                        guard let start = calendar.date(byAdding: .minute, value: startMinute, to: baseStart) else {
                            continue
                        }

                        let session = TrackingSession(
                            startDate: start,
                            endDate: start.addingTimeInterval(TimeInterval(segmentMinutes * 60)),
                            appName: sessionContext.appName,
                            bundleIdentifier: sessionContext.bundleIdentifier,
                            domain: sessionContext.domain,
                            filePath: sessionContext.filePath,
                            source: sessionContext.source,
                            project: project,
                        )
                        context.insert(session)
                        project.sessions.append(session)
                        dayTotalMinutes += segmentMinutes
                    }

                    guard dayTotalMinutes > 0 else { continue }
                    let summary = DailySummary(
                        date: dayDate,
                        seconds: TimeInterval(dayTotalMinutes * 60),
                        project: project,
                    )
                    context.insert(summary)
                    project.dailySummaries.append(summary)
                }
            }

            let pendingAppConflict = PendingTrackingSession(
                startDate: now.addingTimeInterval(-35 * 60),
                endDate: now.addingTimeInterval(-5 * 60),
                appName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                domain: nil,
                filePath: nil,
                contextType: AssignmentContextType.app.rawValue,
                contextValue: "com.microsoft.VSCode",
            )
            context.insert(pendingAppConflict)

            let pendingDomainConflict = PendingTrackingSession(
                startDate: now.addingTimeInterval(-90 * 60),
                endDate: now.addingTimeInterval(-45 * 60),
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                domain: "linear.app",
                filePath: nil,
                contextType: AssignmentContextType.domain.rawValue,
                contextValue: "linear.app",
            )
            context.insert(pendingDomainConflict)

            if let productBuild = projectsByName["Product Build"] {
                let ruleDate = now.addingTimeInterval(-60 * 60 * 24 * 18)
                let xcodeRule = AssignmentRule(
                    contextType: AssignmentContextType.app.rawValue,
                    contextValue: "com.apple.dt.Xcode",
                    project: productBuild,
                    createdAt: ruleDate,
                    lastUsedAt: ruleDate.addingTimeInterval(60 * 60 * 24 * 2),
                )
                context.insert(xcodeRule)
            }

            if let docs = projectsByName["Documentation"] {
                let ruleDate = now.addingTimeInterval(-60 * 60 * 24 * 12)
                let docsRule = AssignmentRule(
                    contextType: AssignmentContextType.domain.rawValue,
                    contextValue: "docs.google.com",
                    project: docs,
                    createdAt: ruleDate,
                    lastUsedAt: ruleDate.addingTimeInterval(60 * 60 * 24 * 3),
                )
                context.insert(docsRule)
            }

            try? context.save()
        }
    #endif
}
