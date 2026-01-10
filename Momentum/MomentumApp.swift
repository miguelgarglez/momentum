//
//  MomentumApp.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftData
import SwiftUI
#if os(macOS)
    import AppKit
#endif

@main
@MainActor
struct MomentumApp: App {
    @StateObject private var trackerSettings: TrackerSettings
    @StateObject private var environment: AppEnvironment
    @StateObject private var onboardingState = OnboardingState()
    @StateObject private var automationPermissionManager = AutomationPermissionManager()
    @StateObject private var trackingSessionManager = TrackingSessionManager()
    @StateObject private var themePreview = ThemePreviewState()
    @State private var bootstrapError: String?
    @State private var isBootstrapping = false

    init() {
        let settings = TrackerSettings()
        _trackerSettings = StateObject(wrappedValue: settings)
        _environment = StateObject(wrappedValue: AppEnvironment(trackerSettings: settings))
    }

    var body: some Scene {
        let effectiveThemePreference = themePreview.previewPreference ?? trackerSettings.themePreference
        WindowGroup {
            Group {
                if let container = environment.container,
                   let tracker = environment.tracker
                {
                    ContentView()
                        .environmentObject(tracker)
                        .environmentObject(environment.trackerSettings)
                        .environmentObject(environment.appCatalog)
                        .environmentObject(onboardingState)
                        .environmentObject(automationPermissionManager)
                        .environmentObject(trackingSessionManager)
                        .environmentObject(themePreview)
                        .modelContainer(container)
                } else if let bootstrapError {
                    VStack(spacing: 8) {
                        Text("No pudimos preparar Momentum")
                            .font(.headline)
                        Text(bootstrapError)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ProgressView("Preparando Momentum…")
                        .padding()
                }
            }
            .task {
                await bootstrapIfNeeded()
            }
            .preferredColorSchemeIfNeeded(effectiveThemePreference.colorScheme)
            #if os(macOS)
                .task(id: effectiveThemePreference) {
                    applyAppearance(for: effectiveThemePreference)
                }
            #endif
        }

        Settings {
            Group {
                if let container = environment.container {
                    TrackerSettingsView()
                        .environmentObject(environment.trackerSettings)
                        .environmentObject(environment.appCatalog)
                        .environmentObject(onboardingState)
                        .environmentObject(automationPermissionManager)
                        .environmentObject(trackingSessionManager)
                        .environmentObject(themePreview)
                        .modelContainer(container)
                } else {
                    ProgressView("Cargando ajustes…")
                        .padding()
                }
            }
            .task {
                await bootstrapIfNeeded()
            }
            .preferredColorSchemeIfNeeded(effectiveThemePreference.colorScheme)
            #if os(macOS)
                .task(id: effectiveThemePreference) {
                    applyAppearance(for: effectiveThemePreference)
                }
            #endif
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 360)

        #if os(macOS)
            WindowGroup(id: OnboardingWindowID.welcome) {
                Group {
                    if let container = environment.container,
                       let tracker = environment.tracker
                    {
                        OnboardingWelcomeWindowView()
                            .environmentObject(tracker)
                            .environmentObject(environment.trackerSettings)
                            .environmentObject(environment.appCatalog)
                            .environmentObject(onboardingState)
                            .environmentObject(automationPermissionManager)
                            .environmentObject(trackingSessionManager)
                            .environmentObject(themePreview)
                            .modelContainer(container)
                    } else {
                        ProgressView("Preparando Momentum…")
                            .padding()
                    }
                }
                .task {
                    await bootstrapIfNeeded()
                }
                .preferredColorSchemeIfNeeded(effectiveThemePreference.colorScheme)
                .task(id: effectiveThemePreference) {
                    applyAppearance(for: effectiveThemePreference)
                }
            }
            .windowResizability(.contentSize)
            .defaultSize(width: 480, height: 460)
        #endif
    }

    #if os(macOS)
        private func applyAppearance(for preference: AppThemePreference) {
            let appearance: NSAppearance?
            switch preference {
            case .system:
                appearance = nil
            case .light:
                appearance = NSAppearance(named: .aqua)
            case .dark:
                appearance = NSAppearance(named: .darkAqua)
            }
            NSApp.appearance = appearance
            for window in NSApp.windows {
                window.appearance = appearance
            }
        }
    #endif

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !environment.isConfigured, !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            let configuration = Self.storeConfiguration()
            if configuration.shouldReset {
                Self.resetPersistentStore(at: configuration.directory)
            }
            try environment.configure(storeDirectory: configuration.directory, isUITest: Self.isUITestRun)
            bootstrapError = nil
        } catch {
            bootstrapError = error.localizedDescription
        }
    }
}

// MARK: - Store configuration

private struct StoreConfiguration {
    let directory: URL
    let shouldReset: Bool
}

private extension MomentumApp {
    static func storeConfiguration() -> StoreConfiguration {
        let directory = resolveStoreDirectory()
        let shouldReset = CommandLine.arguments.contains("--uitests-reset")
        return StoreConfiguration(directory: directory, shouldReset: shouldReset)
    }

    static var isUITestRun: Bool {
        CommandLine.arguments.contains("--uitests") || ProcessInfo.processInfo.environment["UITESTS"] == "1"
    }

    static var shouldSeedConflicts: Bool {
        CommandLine.arguments.contains("--seed-conflicts")
    }

    static var shouldSeedRules: Bool {
        CommandLine.arguments.contains("--seed-rules")
    }

    static var shouldSkipDebugSeed: Bool {
        CommandLine.arguments.contains("--skip-debug-seed")
            || ProcessInfo.processInfo.environment["MOMENTUM_SKIP_DEBUG_SEED"] == "1"
    }

    static func makeStoreURL(in directory: URL) -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Failed to create store directory: \(error.localizedDescription)")
        }
        return directory.appendingPathComponent("Momentum.sqlite")
    }

    static func resolveStoreDirectory() -> URL {
        if let custom = customStoreDirectory() {
            return custom
        }
        return defaultStoreDirectory()
    }

    static func customStoreDirectory() -> URL? {
        if let cliPath = storePathArgument() {
            return URL(fileURLWithPath: cliPath, isDirectory: true)
        }
        if let envPath = ProcessInfo.processInfo.environment["MOMENTUM_STORE_PATH"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath, isDirectory: true)
        }
        return nil
    }

    static func storePathArgument() -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--store-path"),
              CommandLine.arguments.count > index + 1
        else {
            return nil
        }
        return CommandLine.arguments[index + 1]
    }

    static func defaultStoreDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MomentumStore", isDirectory: true)
    }

    static func resetPersistentStore(at directory: URL) {
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            NSLog("Failed to reset store directory: \(error.localizedDescription)")
        }
    }
}

// MARK: - Environment bootstrap

@MainActor
final class AppEnvironment: ObservableObject {
    let trackerSettings: TrackerSettings
    let appCatalog = AppCatalog()
    private(set) var container: ModelContainer?
    @Published private(set) var tracker: ActivityTracker?
    private var dataProtection: DataProtectionCoordinator?
    private let dailySummaryBackfill: DailySummaryBackfilling = DailySummaryBackfill()
    #if os(macOS)
        private var statusItemCoordinator = StatusItemCoordinator()
    #endif

    init(trackerSettings: TrackerSettings) {
        self.trackerSettings = trackerSettings
    }

    var isConfigured: Bool {
        container != nil && tracker != nil
    }

    func configure(storeDirectory: URL) throws {
        try configure(storeDirectory: storeDirectory, isUITest: MomentumApp.isUITestRun)
    }

    func configure(storeDirectory: URL, isUITest: Bool) throws {
        guard container == nil else { return }

        let schema = Schema([
            Project.self,
            AssignmentRule.self,
            PendingTrackingSession.self,
            TrackingSession.self,
            DailySummary.self,
        ])
        let configuration: ModelConfiguration
        if isUITest {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            let storeURL = MomentumApp.makeStoreURL(in: storeDirectory)
            configuration = ModelConfiguration(
                "MomentumStore",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])
        #if DEBUG
            if !isUITest, !MomentumApp.shouldSkipDebugSeed {
                seedDebugDataIfNeeded(in: container)
            }
        #endif
        if isUITest, MomentumApp.shouldSeedConflicts {
            seedPendingConflicts(in: container)
        }
        if isUITest, MomentumApp.shouldSeedRules {
            seedAssignmentRules(in: container)
        }
        let performanceMonitor: PerformanceBudgetMonitoring = isUITest ? NoopPerformanceBudgetMonitor() : PerformanceBudgetMonitor()
        let crashRecovery: CrashRecoveryHandling = isUITest ? NoopCrashRecoveryManager() : CrashRecoveryManager()
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: trackerSettings,
            crashRecovery: crashRecovery,
            performanceMonitor: performanceMonitor
        )
        let dataProtection = isUITest ? nil : DataProtectionCoordinator(container: container, settings: trackerSettings)

        self.container = container
        self.tracker = tracker
        self.dataProtection = dataProtection
        #if os(macOS)
            statusItemCoordinator.configure(with: tracker)
        #endif
        if !isUITest {
            dailySummaryBackfill.runIfNeeded(container: container)
        }
    }
}

private extension AppEnvironment {
    func seedPendingConflicts(in container: ModelContainer) {
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
            contextValue: bundleID
        )
        let domainSession = PendingTrackingSession(
            startDate: now.addingTimeInterval(-420),
            endDate: now.addingTimeInterval(-120),
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            domain: domain,
            filePath: nil,
            contextType: AssignmentContextType.domain.rawValue,
            contextValue: domain
        )
        context.insert(appSession)
        context.insert(domainSession)

        try? context.save()
    }

    func seedAssignmentRules(in container: ModelContainer) {
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
            lastUsedAt: referenceDate
        )
        context.insert(rule)

        try? context.save()
    }

    #if DEBUG
        func seedDebugDataIfNeeded(in container: ModelContainer) {
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
                domain: String? = nil
            ) {
                guard let start = calendar.date(byAdding: .hour, value: startHour, to: day(dayOffset)) else { return }
                let session = TrackingSession(
                    startDate: start,
                    endDate: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
                    appName: appName,
                    bundleIdentifier: bundleID,
                    domain: domain,
                    filePath: nil,
                    project: project
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
                assignedDomains: ["developer.apple.com"]
            )
            let writing = Project(
                name: "Writing",
                assignedApps: ["com.apple.iWork.Pages"],
                assignedDomains: ["docs.google.com"]
            )
            let admin = Project(
                name: "Admin",
                assignedApps: ["com.apple.Mail", "com.apple.Calendar"],
                assignedDomains: []
            )

            let conflictBundle = "com.microsoft.VSCode"
            let conflictDomain = "docs.seed.local"
            let courseA = Project(name: "Curso A", assignedApps: [conflictBundle], assignedDomains: [conflictDomain])
            let courseB = Project(name: "Curso B", assignedApps: [conflictBundle], assignedDomains: [conflictDomain])

            [deepWork, writing, admin, courseA, courseB].forEach { context.insert($0) }

            addSession(project: deepWork, dayOffset: 0, startHour: 9, durationMinutes: 120, appName: "Xcode", bundleID: "com.apple.dt.Xcode")
            addSession(project: deepWork, dayOffset: 1, startHour: 10, durationMinutes: 90, appName: "Xcode", bundleID: "com.apple.dt.Xcode")
            addSession(project: deepWork, dayOffset: 2, startHour: 11, durationMinutes: 45, appName: "Xcode", bundleID: "com.apple.dt.Xcode")

            addSession(project: writing, dayOffset: 0, startHour: 14, durationMinutes: 60, appName: "Pages", bundleID: "com.apple.iWork.Pages", domain: "docs.google.com")
            addSession(project: writing, dayOffset: 1, startHour: 15, durationMinutes: 30, appName: "Pages", bundleID: "com.apple.iWork.Pages", domain: "docs.google.com")
            addSession(project: writing, dayOffset: 2, startHour: 13, durationMinutes: 90, appName: "Pages", bundleID: "com.apple.iWork.Pages", domain: "docs.google.com")

            addSession(project: admin, dayOffset: 0, startHour: 17, durationMinutes: 25, appName: "Mail", bundleID: "com.apple.Mail")

            addSummary(project: deepWork, dayOffset: 0, minutes: 120)
            addSummary(project: deepWork, dayOffset: 1, minutes: 90)
            addSummary(project: deepWork, dayOffset: 2, minutes: 45)
            addSummary(project: writing, dayOffset: 0, minutes: 60)
            addSummary(project: writing, dayOffset: 1, minutes: 30)
            addSummary(project: writing, dayOffset: 2, minutes: 90)
            addSummary(project: admin, dayOffset: 0, minutes: 25)

            let pendingAppConflict = PendingTrackingSession(
                startDate: now.addingTimeInterval(-900),
                endDate: now.addingTimeInterval(-600),
                appName: "VSCode",
                bundleIdentifier: conflictBundle,
                domain: nil,
                filePath: nil,
                contextType: AssignmentContextType.app.rawValue,
                contextValue: conflictBundle
            )
            let pendingDomainConflict = PendingTrackingSession(
                startDate: now.addingTimeInterval(-1800),
                endDate: now.addingTimeInterval(-1200),
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                domain: conflictDomain,
                filePath: nil,
                contextType: AssignmentContextType.domain.rawValue,
                contextValue: conflictDomain
            )
            context.insert(pendingAppConflict)
            context.insert(pendingDomainConflict)

            let ruleDate = now.addingTimeInterval(-60 * 60 * 24 * 7)
            let rule = AssignmentRule(
                contextType: AssignmentContextType.app.rawValue,
                contextValue: "com.apple.dt.Xcode",
                project: deepWork,
                createdAt: ruleDate,
                lastUsedAt: ruleDate
            )
            context.insert(rule)

            try? context.save()
            defaults.set(true, forKey: seedKey)
        }
    #endif
}

private extension View {
    @ViewBuilder
    func preferredColorSchemeIfNeeded(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            preferredColorScheme(scheme)
        } else {
            self
        }
    }
}
