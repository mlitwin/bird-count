import SwiftUI

struct NumericPad: View {
    let onDigit: (Int) -> Void
    let onBack: () -> Void
    let onClear: () -> Void

    private let layout: [[Int?]] = [[1,2,3],[4,5,6],[7,8,9],[nil,0,nil]]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(layout.indices, id: \.self) { r in
                HStack(spacing: 12) {
                    ForEach(layout[r].indices, id: \.self) { c in
                        if let val = layout[r][c] {
                            PadButton { onDigit(val) } label: { Text("\(val)").font(.title2.bold()) }
                        } else if r == 3 && c == 0 {
                            PadButton { onBack() } label: { Image(systemName: "delete.left").font(.title2) }
                        } else if r == 3 && c == 2 {
                            PadButton { onClear() } label: { Image(systemName: "xmark").font(.title2) }
                        } else {
                            Spacer().frame(width: 64, height: 64)
                        }
                    }
                }
            }
        }
    }
}

private struct PadButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    var body: some View {
        Button(action: action) {
            label
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }
}
