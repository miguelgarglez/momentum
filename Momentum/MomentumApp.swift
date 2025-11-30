//
//  MomentumApp.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI
import SwiftData

@main
struct MomentumApp: App {
    @StateObject private var environment = AppEnvironment()
    @State private var bootstrapError: String?
    @State private var isBootstrapping = false
#if os(macOS)
    @NSApplicationDelegateAdaptor(MomentumAppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = environment.container,
                   let tracker = environment.tracker {
                    ContentView()
                        .environmentObject(tracker)
                        .environmentObject(environment.trackerSettings)
                        .environmentObject(environment.appCatalog)
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
        }

        Settings {
            Group {
                if let container = environment.container {
                    TrackerSettingsView()
                        .environmentObject(environment.trackerSettings)
                        .environmentObject(environment.appCatalog)
                        .modelContainer(container)
                } else {
                    ProgressView("Cargando ajustes…")
                        .padding()
                }
            }
            .task {
                await bootstrapIfNeeded()
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 360)
    }

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
#if os(macOS)
            if let tracker = environment.tracker {
                appDelegate.trackerProvider = { tracker }
            }
#endif
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
              CommandLine.arguments.count > index + 1 else {
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
    let trackerSettings = TrackerSettings()
    let appCatalog = AppCatalog()
    private(set) var container: ModelContainer?
    @Published private(set) var tracker: ActivityTracker?
    private var dataProtection: DataProtectionCoordinator?

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
            TrackingSession.self,
            DailySummary.self
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
        let performanceMonitor: PerformanceBudgetMonitoring = isUITest ? NoopPerformanceBudgetMonitor() : PerformanceBudgetMonitor()
        let tracker = ActivityTracker(
            modelContainer: container,
            settings: trackerSettings,
            crashRecovery: CrashRecoveryManager(),
            performanceMonitor: performanceMonitor
        )
        let dataProtection = isUITest ? nil : DataProtectionCoordinator(container: container, settings: trackerSettings)

        self.container = container
        self.tracker = tracker
        self.dataProtection = dataProtection
    }
}
