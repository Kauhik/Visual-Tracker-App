import SwiftUI

@main
struct Visual_Tracker_AppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CloudKitStore()
    @StateObject private var activityCenter = ActivityCenter()
    @State private var zoomManager = ZoomManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(activityCenter)
                .environment(zoomManager)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Section {
                    Button("Zoom In") { zoomManager.zoomIn() }
                        .keyboardShortcut("+", modifiers: [.command])

                    Button("Zoom Out") { zoomManager.zoomOut() }
                        .keyboardShortcut("-", modifiers: [.command])

                    Button("Actual Size") { zoomManager.reset() }
                        .keyboardShortcut("0", modifiers: [.command])
                }
            }
        }
    }
}
