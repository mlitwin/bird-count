import SwiftUI

/// A view that provides spacing to match the floating header by rendering a visible copy.
struct HeaderSpacingView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Visible header structure matching the actual floating header
            AppHeaderView(showSettings: .constant(false))
        }
        .background(
            // Solid background matching systemGroupedBackground
            Color(.systemGroupedBackground)
        )
    }
}

#if DEBUG
#Preview {
    VStack {
        HeaderSpacingView()
        
        Text("Content below header")
        Spacer()
    }
    .environment(ObservationStore())
    .environment(TaxonomyStore())
    .environment(DateRangeStore())
    .environment(SyncSessionManager())
}
#endif
