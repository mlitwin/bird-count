import SwiftUI

/// App header containing the title, settings button, and global observations selector
struct AppHeaderView: View {
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar: centered title with trailing Settings button
            ZStack {
                Text("Bird Count")
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.headline)
                        .padding(8)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Global observations selector
            ObservationsSelectorView()
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }
}
