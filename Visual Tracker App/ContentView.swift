import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CloudKitStore
    @EnvironmentObject private var activityCenter: ActivityCenter
    @Environment(ZoomManager.self) private var zoomManager

    @State private var selectedGroup: CohortGroup?
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingICloudPrompt: Bool = false
    @State private var loadingActivityToken: UUID?

    private var students: [Student] {
        store.students
    }

    private var studentIds: [UUID] {
        students.map(\.id)
    }

    private var selectedStudent: Student? {
        guard let selectedId = store.selectedStudentId else { return nil }
        return students.first { $0.id == selectedId }
    }

    private var selectedStudentBinding: Binding<Student?> {
        Binding(
            get: { selectedStudent },
            set: { newValue in
                store.selectedStudentId = newValue?.id
            }
        )
    }

    private var selectedStudentIdBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedStudentId },
            set: { newValue in
                store.selectedStudentId = newValue
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            StudentOverviewBoard(selectedStudentId: selectedStudentIdBinding)
                .navigationTitle("Students")
        } detail: {
            SwiftUI.Group {
                if students.isEmpty {
                    ContentUnavailableView(
                        "No Students",
                        systemImage: "person.3",
                        description: Text("Add a student to start tracking progress.")
                    )
                } else {
                    StudentDetailView(
                        selectedStudent: selectedStudentBinding,
                        selectedGroup: $selectedGroup
                    )
                }
            }
            .navigationTitle("Visual Tracker")
        }
        .dynamicTypeSize(zoomManager.dynamicTypeSize)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ActivityStatusView(activity: activityCenter)
            }
        }
        .onChange(of: studentIds) { _, newIds in
            if let selectedId = store.selectedStudentId, newIds.contains(selectedId) == false {
                store.selectedStudentId = nil
            }
        }
        .onChange(of: store.activeSheet?.id) { _, _ in
            selectedGroup = nil
            store.selectedStudentId = nil
            store.selectedScope = .overall
        }
        .task {
            await store.loadIfNeeded()
            await store.ensurePresetDomains()
        }
        .overlay {
            if let resetProgress = store.resetProgress {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    VStack(spacing: zoomManager.scaled(12)) {
                        ProgressView(
                            value: Double(resetProgress.step),
                            total: Double(max(resetProgress.totalSteps, 1))
                        )
                        .progressViewStyle(.linear)
                        Text("Resetting...")
                            .font(.headline)
                        Text(resetProgress.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(zoomManager.scaled(20))
                    .background(
                        RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
            } else if store.shouldShowBlockingLoadingUI {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("Loading Cloud Data…")
                        .padding(zoomManager.scaled(20))
                        .background(
                            RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                }
            }
        }
        .overlay(alignment: .top) {
            if store.requiresICloudLogin || store.cacheStatusMessage != nil {
                VStack(spacing: zoomManager.scaled(8)) {
                    if store.requiresICloudLogin {
                        HStack(spacing: zoomManager.scaled(12)) {
                            Image(systemName: "icloud.slash")
                                .font(.title3)

                            VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                                Text("Read-only mode")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Sign in to iCloud to enable edits and syncing.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Open iCloud Settings") {
                                store.openICloudSettings()
                            }
                            .buttonStyle(.bordered)

                            Button("Retry") {
                                Task { await store.reloadAllData() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(zoomManager.scaled(12))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: zoomManager.scaled(12)))
                        .overlay(
                            RoundedRectangle(cornerRadius: zoomManager.scaled(12))
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }

                    if let cacheStatusMessage = store.cacheStatusMessage {
                        HStack(spacing: zoomManager.scaled(8)) {
                            Image(systemName: store.isOfflineUsingSnapshot ? "wifi.exclamationmark" : "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(cacheStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, zoomManager.scaled(10))
                        .padding(.vertical, zoomManager.scaled(6))
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: zoomManager.scaled(10)))
                    }
                }
                .padding(.horizontal, zoomManager.scaled(16))
                .padding(.top, zoomManager.scaled(12))
            }
        }
        .alert("CloudKit Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("iCloud Sign-In Required", isPresented: $showingICloudPrompt) {
            Button("Open iCloud Settings") {
                store.openICloudSettings()
            }
            Button("Retry") {
                Task { await store.reloadAllData() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To enable edits and CloudKit access, sign in to iCloud on this Mac.")
        }
        .onChange(of: store.lastErrorMessage) { _, newValue in
            if let newValue {
                errorMessage = newValue
                showingError = true
            }
        }
        .onChange(of: store.requiresICloudLogin) { _, newValue in
            if newValue {
                showingICloudPrompt = true
            }
        }
        .onChange(of: store.isLoading) { _, newValue in
            if newValue {
                if loadingActivityToken == nil {
                    loadingActivityToken = activityCenter.begin(message: "Loading cloud data…")
                }
            } else if let token = loadingActivityToken {
                activityCenter.end(token)
                loadingActivityToken = nil
            }
        }
    }

}

#Preview {
    ContentView()
        .environmentObject(CloudKitStore(usePreviewData: true))
        .environmentObject(ActivityCenter())
        .environment(ZoomManager())
}
