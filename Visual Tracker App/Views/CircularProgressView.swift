import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    @Environment(ZoomManager.self) private var zoomManager

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: zoomManager.scaled(6))

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: zoomManager.scaled(6), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((max(0, min(1, progress))) * 100)) percent")
    }
}
