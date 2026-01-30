import SwiftUI

@main
struct Visual_Tracker_AppApp: App {
    @StateObject private var store = CloudKitStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
