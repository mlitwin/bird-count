import SwiftUI

/// App header containing the title, menu button, and global observations selector
struct AppHeaderView: View {
    @Binding var showSettings: Bool
    @Binding var showLeftDrawer: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar: centered title with leading menu button
            ZStack {
                Text(Strings.Home.title.string)
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showLeftDrawer = true
                    }
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.headline)
                        .padding(8)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel(Strings.General.menu.string)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Global observations selector
            ObservationsSelectorView()
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .background(
            // Gradient background that transitions from opaque to transparent
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(.systemGroupedBackground), location: 0.95),
                    .init(color: Color(.systemGroupedBackground).opacity(0.5), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
