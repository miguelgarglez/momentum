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
    #if os(macOS)
        @NSApplicationDelegateAdaptor(MomentumAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var trackerSettings: TrackerSettings
    @StateObject private var environment: AppEnvironment
    @StateObject private var onboardingState = OnboardingState()
    @StateObject private var automationPermissionManager = AutomationPermissionManager()
    @StateObject private var trackingSessionManager = TrackingSessionManager()
    @StateObject private var themePreview = ThemePreviewState()
    @State private var bootstrapError: String?
    @State private var isBootstrapping = false
    @State private var didSeedDiagnostics = false

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
                        .environmentObject(environment.raycastIntegrationManager)
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
            settingsContent(effectiveThemePreference: effectiveThemePreference)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 620, height: 460)

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
                            .environmentObject(environment.raycastIntegrationManager)
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
            let appearance: NSAppearance? = switch preference {
            case .system:
                nil
            case .light:
                NSAppearance(named: .aqua)
            case .dark:
                NSAppearance(named: .darkAqua)
            }
            NSApp.appearance = appearance
            for window in NSApp.windows {
                window.appearance = appearance
            }
        }
    #endif

    @ViewBuilder
    private func settingsContent(effectiveThemePreference: AppThemePreference) -> some View {
        Group {
            if let container = environment.container {
                SettingsShellView()
                    .environmentObject(environment.trackerSettings)
                    .environmentObject(environment.appCatalog)
                    .environmentObject(environment.raycastIntegrationManager)
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
            .background(WindowCloseAccessoryHandler())
        #endif
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !environment.isConfigured, !isBootstrapping else { return }
        if Self.isDiagnosticsSeedRun, didSeedDiagnostics {
            return
        }
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            let configuration = Self.storeConfiguration()
            if configuration.shouldReset {
                Self.resetPersistentStore(at: configuration.directory)
            }
            try environment.configure(
                storeDirectory: configuration.directory,
                isUITest: Self.isUITestRun,
                isSeedRun: Self.isDiagnosticsSeedRun,
            )
            bootstrapError = nil
            if Self.isDiagnosticsSeedRun {
                didSeedDiagnostics = true
                Self.terminateAfterSeeding()
            }
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

    static var isDiagnosticsSeedRun: Bool {
        CommandLine.arguments.contains("--seed-diagnostics-store")
            || ProcessInfo.processInfo.environment["MOM_DIAG_PRESEED"] == "1"
    }

    static func terminateAfterSeeding() {
        #if os(macOS)
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        #else
            exit(0)
        #endif
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
    let raycastIntegrationManager: RaycastIntegrationManager
    private(set) var container: ModelContainer?
    @Published private(set) var tracker: ActivityTracker?
    private var dataProtection: DataProtectionCoordinator?
    private let dailySummaryBackfill: DailySummaryBackfilling = DailySummaryBackfill()
    #if os(macOS)
        private var statusItemCoordinator = StatusItemCoordinator()
        private var dockVisibilityCoordinator = DockVisibilityCoordinator()
    #endif

    init(trackerSettings: TrackerSettings) {
        self.trackerSettings = trackerSettings
        raycastIntegrationManager = RaycastIntegrationManager(settings: trackerSettings)
        #if os(macOS)
            NSApp.setActivationPolicy(.accessory)
            dockVisibilityCoordinator.start()
        #endif
    }

    var isConfigured: Bool {
        container != nil && tracker != nil
    }

    func configure(storeDirectory: URL) throws {
        try configure(
            storeDirectory: storeDirectory,
            isUITest: MomentumApp.isUITestRun,
            isSeedRun: MomentumApp.isDiagnosticsSeedRun,
        )
    }

    func configure(storeDirectory: URL, isUITest: Bool, isSeedRun: Bool) throws {
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
                cloudKitDatabase: .none,
            )
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])
        if isSeedRun {
            DiagnosticsSeedData.seedDiagnosticsDataIfNeeded(in: container)
            self.container = container
            return
        }
        #if DEBUG
            if !isUITest, !MomentumApp.shouldSkipDebugSeed {
                SeedData.seedDebugDataIfNeeded(in: container)
            }
        #endif
        if isUITest, MomentumApp.shouldSeedConflicts {
            SeedData.seedPendingConflicts(in: container)
        }
        if isUITest, MomentumApp.shouldSeedRules {
            SeedData.seedAssignmentRules(in: container)
        }
        let performanceMonitor: PerformanceBudgetMonitoring = isUITest ? NoopPerformanceBudgetMonitor() : PerformanceBudgetMonitor()
        let crashRecovery: CrashRecoveryHandling = isUITest ? NoopCrashRecoveryManager() : CrashRecoveryManager()
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: trackerSettings,
            crashRecovery: crashRecovery,
            performanceMonitor: performanceMonitor,
        )
        let dataProtection = isUITest ? nil : DataProtectionCoordinator(container: container, settings: trackerSettings)

        self.container = container
        self.tracker = tracker
        self.dataProtection = dataProtection
        raycastIntegrationManager.configure(
            modelContainer: container,
            isUITest: isUITest,
            isSeedRun: isSeedRun,
        )
        #if os(macOS)
            statusItemCoordinator.configure(with: tracker)
        #endif
        if !isUITest {
            dailySummaryBackfill.runIfNeeded(container: container)
        }
    }
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
