import SwiftUI

struct OnScreenKeyboard: View {
    let onKey: (String) -> Void
    let onBackspace: () -> Void
    let onClear: () -> Void

    // Always active on Home; keep as a parameter for flexibility
    var active: Bool = true
    var bottomPadding: CGFloat = 8
    var topPadding: CGFloat = 8
    var rowSpacing: CGFloat = 10
    private let rows: [[String]] = [
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"],
    ]

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { key in
                        KeyButton(label: key, flex: true, active: active) { onKey(key.lowercased()) }
                    }
                    if r == rows.count - 1 {
                        KeyButton(symbol: "delete.left.fill", flex: true, role: .destructive, active: active) { onBackspace() }
                    }
                }
            }
        }
    .padding(.horizontal, 10)
    .padding(.top, topPadding)
    .padding(.bottom, bottomPadding)
        // Slight active halo around the keyboard area
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(active ? Color.accentColor.opacity(0.25) : .clear, lineWidth: 1)
        )
    }
}

private struct KeyButton: View {
    var label: String? = nil
    var symbol: String? = nil
    var width: CGFloat? = nil
    var flex: Bool = false
    var role: ButtonRole? = nil
    var active: Bool = true
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
        // Visible pressed feedback via custom style (highlight + slight scale)
        .buttonStyle(KeyCapsStyle(active: active, isAction: label == nil, flex: flex, explicitWidth: width))
    }
}

// MARK: - Button style for visible pressed feedback
private struct KeyCapsStyle: ButtonStyle {
    var active: Bool
    var isAction: Bool // true for symbol/action keys
    var flex: Bool
    var explicitWidth: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Base sizing similar to original
            .padding(.vertical, 4)
            .frame(height: 46)
            .frame(maxWidth: flex ? .infinity : (explicitWidth ?? 34))
            // Background fill (white for letters, secondary fill for action keys)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((isAction ? Color(.secondarySystemFill) : .white)
                        .opacity(configuration.isPressed ? 0.92 : 1.0))
            )
            // Pressed highlight overlay
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.15 : 0))
            )
            // Border accent changes slightly when pressed
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(active ? Color.accentColor.opacity(configuration.isPressed ? 0.35 : 0.2) : .clear, lineWidth: 1)
            )
            // Subtle scale for tactile feel
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
