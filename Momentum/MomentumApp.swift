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
    @StateObject private var appCatalog = AppCatalog()

    init() {
        let schema = Schema([
            Project.self,
            TrackingSession.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            sharedModelContainer = container
            _tracker = StateObject(wrappedValue: ActivityTracker(modelContainer: container))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(appCatalog)
        }
        .modelContainer(sharedModelContainer)
    }
}
