import Foundation
import SwiftUI
import Combine

@MainActor
final class ActivityCenter: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    enum Tag {
        case general
        case detail
    }

    struct Activity {
        let message: String
        let progress: Double?
        let tag: Tag
        let startedAt: Date
    }

    @Published private(set) var isVisible: Bool = false
    @Published private(set) var message: String?
    @Published private(set) var progress: Double?
    @Published private(set) var tag: Tag = .general

    private var active: [UUID: Activity] = [:]
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var visibleSince: Date?

    private let showDelay: TimeInterval = 0.35
    private let minimumVisible: TimeInterval = 0.25

    func begin(message: String, tag: Tag = .general, progress: Double? = nil) -> UUID {
        let token = UUID()
        active[token] = Activity(message: message, progress: progress, tag: tag, startedAt: Date())
        hideTask?.cancel()
        hideTask = nil
        updateCurrentActivity()
        scheduleShowIfNeeded()
        return token
    }

    func end(_ token: UUID) {
        active.removeValue(forKey: token)
        updateCurrentActivity()
        if active.isEmpty {
            showTask?.cancel()
            showTask = nil
            scheduleHideIfNeeded()
        }
    }

    func run<T>(
        message: String,
        tag: Tag = .general,
        progress: Double? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        let token = begin(message: message, tag: tag, progress: progress)
        defer { end(token) }
        return try await operation()
    }

    private func scheduleShowIfNeeded() {
        guard isVisible == false else { return }
        showTask?.cancel()
        showTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(showDelay * 1_000_000_000))
            guard Task.isCancelled == false else { return }
            guard active.isEmpty == false else { return }
            visibleSince = Date()
            isVisible = true
            updateCurrentActivity()
        }
    }

    private func scheduleHideIfNeeded() {
        guard isVisible else { return }
        let elapsed = Date().timeIntervalSince(visibleSince ?? Date())
        let remaining = max(0, minimumVisible - elapsed)

        hideTask?.cancel()
        hideTask = Task {
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard Task.isCancelled == false else { return }
            guard active.isEmpty else { return }
            isVisible = false
            message = nil
            progress = nil
        }
    }

    private func updateCurrentActivity() {
        guard let latest = active.values.sorted(by: { $0.startedAt > $1.startedAt }).first else {
            if active.isEmpty && isVisible == false {
                message = nil
                progress = nil
            }
            return
        }

        message = latest.message
        progress = latest.progress
        tag = latest.tag
    }
}

struct ActivityStatusView: View {
    @ObservedObject var activity: ActivityCenter

    var body: some View {
        if activity.isVisible {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)

                if let message = activity.message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else {
            EmptyView()
        }
    }
}
