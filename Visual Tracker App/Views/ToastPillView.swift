import SwiftUI

struct ToastPillView: View {
    enum Style {
        case success
        case info
        case warning
        case error

        var iconName: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .info:
                return "info.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .success:
                return .green
            case .info:
                return .blue
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }

        var borderColor: Color {
            switch self {
            case .success:
                return Color.green.opacity(0.25)
            case .info:
                return Color.blue.opacity(0.22)
            case .warning:
                return Color.orange.opacity(0.28)
            case .error:
                return Color.red.opacity(0.3)
            }
        }
    }

    let style: Style
    let title: String
    let subtitle: String?
    let showsIcon: Bool
    let autoDismissSeconds: Double?
    var onAutoDismiss: (() -> Void)? = nil

    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showsIcon {
                Image(systemName: style.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style.iconColor)
            }

            VStack(alignment: .center, spacing: subtitle == nil ? 0 : 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(style.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard let autoDismissSeconds, autoDismissSeconds > 0, let onAutoDismiss else { return }
            autoDismissTask?.cancel()
            autoDismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(autoDismissSeconds * 1_000_000_000))
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    onAutoDismiss()
                }
            }
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
    }

    private var accessibilityLabel: Text {
        if let subtitle, subtitle.isEmpty == false {
            return Text("\(title), \(subtitle)")
        }
        return Text(title)
    }
}
