//
//  Visual_Tracker_AppApp.swift
//  Visual Tracker App
//
//  Created by Kaushik Manian on 27/1/26.
//

import SwiftUI
import SwiftData

@main
struct Visual_Tracker_AppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Student.self,
            LearningObjective.self,
            ObjectiveProgress.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    SeedDataService.seedIfNeeded(modelContext: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}
