import SwiftUI

/// Rectangular count badge shared by SpeciesRow and ObservationRecordView.
struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.headline.monospacedDigit())
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
    }
}
