import SwiftUI

struct LogView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HeaderSpacingView()
                ObservationLogContent(bottomAnchored: true)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#if DEBUG
#Preview("Log") {
    LogView()
        .environment(ObservationStore.previewInstance)
        .environment(TaxonomyStore())
        .environment(SettingsStore())
        .environment(DateRangeStore())
        .environment(AppNavigationState())
}
#endif
