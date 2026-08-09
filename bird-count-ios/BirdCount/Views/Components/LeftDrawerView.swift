import SwiftUI

struct LeftDrawerView: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: AppTab
    @Binding var showSettings: Bool
    @Environment(ObservationStore.self) private var observations
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(DateRangeStore.self) private var dateRangeStore

    @State private var showSyncSheet: Bool = false
    @State private var shareSheet: Bool = false
    @State private var importSheet: Bool = false

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
            }

            HStack {
                if isPresented {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(Strings.General.menu.string)
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGroupedBackground))

                        Divider()

                        VStack(spacing: 0) {
                            DrawerMenuSection(title: "Navigate") {
                                DrawerMenuItem(
                                    icon: "house.fill",
                                    title: Strings.Tab.home.string,
                                    isSelected: selectedTab == .home
                                ) {
                                    selectedTab = .home
                                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                                }
                                DrawerMenuItem(
                                    icon: "chart.bar",
                                    title: Strings.Tab.summary.string,
                                    isSelected: selectedTab == .summary
                                ) {
                                    selectedTab = .summary
                                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                                }
                                DrawerMenuItem(
                                    icon: "list.bullet",
                                    title: Strings.Tab.log.string,
                                    isSelected: selectedTab == .log
                                ) {
                                    selectedTab = .log
                                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                                }
                            }

                            DrawerMenuSection(title: Strings.Share.title.string) {
                                DrawerMenuItem(
                                    icon: "square.and.arrow.down",
                                    title: Strings.Import.importData.string
                                ) {
                                    isPresented = false
                                    importSheet = true
                                }

                                DrawerMenuItem(
                                    icon: "square.and.arrow.up",
                                    title: Strings.Share.export.string,
                                    disabled: observations.totalIndividuals(in: dateRangeStore.dateRange) == 0
                                ) {
                                    isPresented = false
                                    shareSheet = true
                                }

                                DrawerMenuItem(
                                    icon: "iphone.radiowaves.left.and.right",
                                    title: "Sync with Nearby Phones"
                                ) {
                                    isPresented = false
                                    showSyncSheet = true
                                }
                            }

                            DrawerMenuSection(title: Strings.Settings.title.string) {
                                DrawerMenuItem(
                                    icon: "gearshape",
                                    title: Strings.Settings.title.string
                                ) {
                                    isPresented = false
                                    showSettings = true
                                }
                            }
                        }
                        .background(Color(.systemBackground))

                        Spacer()
                    }
                    .frame(width: 320)
                    .background(Color(.systemBackground))
                    .shadow(radius: 10)
                    .transition(.move(edge: .leading))
                }

                Spacer()
            }
        }
        .sheet(isPresented: $shareSheet) {
            ExportSheet()
        }
        .sheet(isPresented: $importSheet) {
            ImportSheet()
        }
        .sheet(isPresented: $showSyncSheet) {
            SyncSheet(
                observationStore: observations,
                settingsStore: settingsStore,
                dateRangeStore: dateRangeStore
            )
        }
    }
}

// MARK: - Supporting Components

private struct DrawerMenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 4)

            content
        }
    }
}

private struct DrawerMenuItem: View {
    let icon: String
    let title: String
    let disabled: Bool
    let isSelected: Bool
    let action: () -> Void

    init(icon: String, title: String, disabled: Bool = false, isSelected: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.disabled = disabled
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundColor(disabled ? .secondary : .accentColor)
                    .frame(width: 22)

                Text(title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(disabled ? .secondary : .primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12))
                    : RoundedRectangle(cornerRadius: 10).fill(Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .disabled(disabled)
        .buttonStyle(PlainButtonStyle())
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        LeftDrawerView(
            isPresented: .constant(true),
            selectedTab: .constant(.home),
            showSettings: .constant(false)
        )
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(DateRangeStore())
        .environment(SettingsStore())
    }
}
#endif
