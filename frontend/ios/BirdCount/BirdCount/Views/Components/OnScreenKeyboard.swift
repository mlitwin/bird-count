import SwiftUI

struct OnScreenKeyboard: View {
    let onKey: (String) -> Void
    let onBackspace: () -> Void
    let onClear: () -> Void

    private let rows: [[String]] = [
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"],
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { key in
                        KeyButton(label: key, flex: true) { onKey(key.lowercased()) }
                    }
                    if r == rows.count - 1 {
                        // Include action keys in-row so all keys share equal width
                        KeyButton(symbol: "delete.left.fill", flex: true, role: .destructive) { onBackspace() }
                        KeyButton(symbol: "xmark.circle", flex: true) { onClear() }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

private struct KeyButton: View {
    var label: String? = nil
    var symbol: String? = nil
    var width: CGFloat? = nil
    var flex: Bool = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role) {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Group {
                if let label = label { Text(label).font(.callout.weight(.semibold)) }
                else if let symbol = symbol { Image(systemName: symbol) }
            }
            .frame(width: width, height: 38)
            .frame(maxWidth: flex ? .infinity : nil)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .frame(height: 46)
        .frame(maxWidth: flex ? .infinity : (width ?? 34))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }
}
