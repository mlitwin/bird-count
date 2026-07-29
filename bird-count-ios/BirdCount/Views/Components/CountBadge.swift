import SwiftUI

/// Rectangular count badge shared by SpeciesRow and ObservationRecordView.
struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.headline.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
    }
}
