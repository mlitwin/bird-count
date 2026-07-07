import SwiftUI

struct CommonnessRangeView: View {
    @Binding var minCommonness: Int
    @Binding var maxCommonness: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text("Show species with commonness between:")
            HStack(spacing: 8) {
                DiscreteRangeSlider(min: $minCommonness, max: $maxCommonness, showMaxThumb: false)
                    .frame(maxWidth: .infinity)
                // Static max badge "C" to mirror previous max thumb appearance
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .overlay(Text("C").font(.caption2.weight(.semibold)).foregroundColor(.white))
                    .accessibilityLabel("Max commonness: Common")
            }
            .padding(.vertical, 8)
            .onAppear {
                // Enforce max = C (3) on load and clamp min accordingly
                maxCommonness = 3
                if minCommonness > maxCommonness { minCommonness = maxCommonness }
            }
            .onChange(of: maxCommonness) { _, newVal in
                if newVal != 3 { maxCommonness = 3 }
            }
            CommonnessLegend()
        }
    }
}

private struct CommonnessLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            legendItem(code: "R", label: "Rare")
            legendItem(code: "S", label: "Scarce")
            legendItem(code: "U", label: "Uncommon")
            legendItem(code: "C", label: "Common")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    private func legendItem(code: String, label: String) -> some View { HStack(spacing: 2) { Text(code).bold(); Text(label) } }
}

// MARK: - Two-thumb discrete slider for values 0...3
private struct DiscreteRangeSlider: View {
    @Binding var min: Int
    @Binding var max: Int
    var showMaxThumb: Bool = true

    private let range = 0...3
    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 22
    private let thumbYOffset: CGFloat = 14 // vertical separation to render one above, one below

    var body: some View {
        GeometryReader { geo in
            let width = Swift.max(geo.size.width, 1)
            let steps = CGFloat(range.upperBound - range.lowerBound)
            let stepW = steps == 0 ? width : width / steps

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: trackHeight/2, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: trackHeight)
                    .offset(y: 0)

                // Selected range highlight
                let minX = xPosition(for: min, stepW: stepW)
                let maxX = xPosition(for: max, stepW: stepW)
                RoundedRectangle(cornerRadius: trackHeight/2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: Swift.max(maxX - minX, 0), height: trackHeight)
                    .offset(x: minX)

                // Ticks
                ForEach(range, id: \.self) { i in
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 4, height: 4)
                        .offset(x: xPosition(for: i, stepW: stepW) - 2, y: 0)
                }

                // Max thumb (above) – optional
                if showMaxThumb {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(radius: 1, y: 1)
                        .overlay(Text(code(for: max)).font(.caption2.weight(.semibold)).foregroundColor(.white))
                        .offset(x: xPosition(for: max, stepW: stepW) - thumbSize/2, y: -thumbYOffset - thumbSize/2)
                        .gesture(dragGesture(isMin: false, width: width, stepW: stepW))
                }

                // Min thumb (below)
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Circle().fill(Color(.systemBackground)))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(radius: 1, y: 1)
                    .overlay(Text(code(for: min)).font(.caption2.weight(.semibold)).foregroundColor(.accentColor))
                    .offset(x: xPosition(for: min, stepW: stepW) - thumbSize/2, y: thumbYOffset + thumbSize/2)
                    .gesture(dragGesture(isMin: true, width: width, stepW: stepW))
            }
            .frame(height: Swift.max(thumbSize * 2, CGFloat(44)))
        }
        .frame(height: 56)
    .onChange(of: min) { _, new in if new > max { max = new } }
    .onChange(of: max) { _, new in if new < min { min = new } }
    }

    private func xPosition(for value: Int, stepW: CGFloat) -> CGFloat {
    let clamped = Swift.max(range.lowerBound, Swift.min(range.upperBound, value))
        return CGFloat(clamped - range.lowerBound) * stepW
    }

    private func dragGesture(isMin: Bool, width: CGFloat, stepW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
        let x = Swift.max(0, Swift.min(width, value.location.x))
                let rawIndex = Int(round(x / stepW)) + range.lowerBound
                if isMin {
            let newMin = Swift.min(Swift.max(range.lowerBound, rawIndex), max)
                    if newMin != min { min = newMin }
                } else {
            let newMax = Swift.max(Swift.min(range.upperBound, rawIndex), min)
                    if newMax != max { max = newMax }
                }
            }
    }

    private func code(for value: Int) -> String {
        switch value {
        case 0: return "R"
        case 1: return "S"
        case 2: return "U"
        case 3: return "C"
        default: return ""
        }
    }
}
