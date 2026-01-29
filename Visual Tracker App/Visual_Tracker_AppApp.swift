import SwiftUI
import SwiftData

@main
struct Visual_Tracker_AppApp: App {
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                Student.self,
                LearningObjective.self,
                ObjectiveProgress.self,
                CohortGroup.self,
                Domain.self,
                CategoryLabel.self,
                StudentCustomProperty.self
            ])

            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let builtContainer = try ModelContainer(for: schema, configurations: [configuration])

            self.container = builtContainer
            let mainContext = builtContainer.mainContext

            Task { @MainActor in
                SeedDataService.seedIfNeeded(modelContext: mainContext)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
