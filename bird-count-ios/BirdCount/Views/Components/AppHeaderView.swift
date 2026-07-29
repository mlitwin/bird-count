import SwiftUI

/// App header containing the title, menu button, and global observations selector
struct AppHeaderView: View {
    @Binding var showSettings: Bool
    @Binding var showLeftDrawer: Bool
    @State private var showUserView: Bool = false
    @Environment(AppNavigationState.self) private var navState

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: centered title with leading menu/back button
            ZStack {
                Text(navState.title ?? Strings.Home.title.string)
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                if let back = navState.backAction {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .padding(8)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .accessibilityLabel(Strings.General.back.string)
                } else {
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
            }
            .overlay(alignment: .trailing) {
                // The badge grows leftward into the empty space beside the
                // centered title; the person button never moves.
                HStack(spacing: 8) {
                    SyncStatusBadge(action: { showUserView = true })
                    Button(action: {
                        showUserView = true
                    }) {
                        Image(systemName: "person.circle")
                            .font(.headline)
                            .padding(8)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .accessibilityLabel(Strings.General.user.string)
                }
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
        .sheet(isPresented: $showUserView) {
            UserView()
        }
    }
}
