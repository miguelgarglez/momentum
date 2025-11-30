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
    let sharedModelContainer: ModelContainer
    @StateObject private var tracker: ActivityTracker
    @StateObject private var trackerSettings: TrackerSettings
    @StateObject private var appCatalog = AppCatalog()
#if os(macOS)
    @NSApplicationDelegateAdaptor(MomentumAppDelegate.self) private var appDelegate
#endif

    init() {
        let settings = TrackerSettings()
        let schema = Schema([
            Project.self,
            TrackingSession.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            sharedModelContainer = container
            _trackerSettings = StateObject(wrappedValue: settings)
            let trackerInstance = ActivityTracker(modelContainer: container, settings: settings)
            _tracker = StateObject(wrappedValue: trackerInstance)
#if os(macOS)
            appDelegate.trackerProvider = { trackerInstance }
#endif
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(trackerSettings)
                .environmentObject(appCatalog)
        }
        .modelContainer(sharedModelContainer)

        Settings {
            TrackerSettingsView()
                .environmentObject(trackerSettings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 360)
    }
}
