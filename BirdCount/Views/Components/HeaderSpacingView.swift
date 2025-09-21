import SwiftUI

/// A view that provides spacing to match the floating header by rendering a visible copy.
/// This includes both the AppHeaderView and the Divider below it, with the same background,
/// ensuring perfect alignment with the actual floating header structure used in BirdCountApp.swift.
struct HeaderSpacingView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Visible header structure matching the actual floating header (AppHeaderView + Divider)
            AppHeaderView(showSettings: .constant(false))
            Divider()
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
