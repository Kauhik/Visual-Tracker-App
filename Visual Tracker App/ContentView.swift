import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CloudKitStore

    @State private var selectedStudent: Student?
    @State private var selectedGroup: CohortGroup?
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingICloudPrompt: Bool = false

    private var students: [Student] {
        store.students
    }

    var body: some View {
        NavigationSplitView {
            StudentOverviewBoard(selectedStudent: $selectedStudent)
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
                        selectedStudent: $selectedStudent,
                        selectedGroup: $selectedGroup
                    )
                }
            }
            .navigationTitle("Visual Tracker")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Reset Data", role: .destructive) { resetData() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if selectedStudent == nil, let first = students.first {
                selectedStudent = first
            }
        }
        .onChange(of: students.count) { _, _ in
            if let selected = selectedStudent, students.contains(where: { $0.id == selected.id }) == false {
                selectedStudent = students.first
            } else if selectedStudent == nil, let first = students.first {
                selectedStudent = first
            }
        }
        .task {
            await store.loadIfNeeded()
            await store.ensurePresetDomains()
        }
        .overlay {
            if let resetProgress = store.resetProgress {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    VStack(spacing: 12) {
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
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
            } else if store.isLoading {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("Loading Cloud Data…")
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                }
            }
        }
        .overlay(alignment: .top) {
            if store.requiresICloudLogin {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
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
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
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
    }

    private func resetData() {
        Task {
            await store.resetAllData()
            selectedStudent = store.students.first
            selectedGroup = nil
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CloudKitStore(usePreviewData: true))
}
