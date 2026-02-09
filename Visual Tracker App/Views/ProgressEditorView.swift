import SwiftUI

struct ProgressEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ZoomManager.self) private var zoomManager

    let title: String
    let currentValue: Int
    let onSave: (Int) -> Void

    @State private var sliderValue: Double

    init(title: String, currentValue: Int, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.currentValue = max(0, min(100, currentValue))
        self.onSave = onSave
        self._sliderValue = State(initialValue: Double(max(0, min(100, currentValue))))
    }

    private var clampedIntValue: Int {
        let value = Int(sliderValue.rounded())
        return max(0, min(100, value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: zoomManager.scaled(16)) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: zoomManager.scaled(2)) {
                    Text("Set Progress")
                        .font(.headline)

                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(clampedIntValue)%")
                    .font(zoomManager.scaledFont(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
            }

            Slider(value: $sliderValue, in: 0...100, step: 5)
                .frame(maxWidth: zoomManager.scaled(340))

            HStack(spacing: zoomManager.scaled(8)) {
                quickButton(0)
                quickButton(25)
                quickButton(50)
                quickButton(75)
                quickButton(100)
            }

            Divider()
                .opacity(0.25)

            HStack(spacing: zoomManager.scaled(10)) {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Clear") {
                    onSave(0)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Mark Complete") {
                    onSave(100)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    onSave(clampedIntValue)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(zoomManager.scaled(16))
        .frame(width: zoomManager.scaled(360))
    }

    private func quickButton(_ value: Int) -> some View {
        Button("\(value)%") {
            sliderValue = Double(value)
            onSave(value)
            dismiss()
        }
        .buttonStyle(.bordered)
    }
}
