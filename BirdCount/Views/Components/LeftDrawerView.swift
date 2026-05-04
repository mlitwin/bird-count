import SwiftUI

struct LeftDrawerView: View {
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool
    @Binding var showShareOptions: Bool
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(DateRangeStore.self) private var dateRangeStore
    @Environment(SettingsStore.self) private var settingsStore

    @State private var showSyncSheet: Bool = false
    @State private var shareSheet: Bool = false
    @State private var importSheet: Bool = false
    
    var body: some View {
        ZStack {
            // Background overlay
            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
            }
            
            // Drawer content
            HStack {
                if isPresented {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
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
                        
                        // Menu items
                        VStack(spacing: 0) {
                            // Share section
                            DrawerMenuSection(title: Strings.Share.title.string) {
                                DrawerMenuItem(
                                    icon: "square.and.arrow.down",
                                    title: Strings.Import.importData.string,
                                    disabled: false
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
                            
                            Divider()
                                .padding(.horizontal)
                            
                            // Settings section
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
                    .frame(width: 280)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 0))
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
    
    // MARK: - Helper Methods - Removed export logic, now in ShareActivitySheet
}

// MARK: - Supporting Components

private struct DrawerMenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 16)
            
            content
        }
    }
}

private struct DrawerMenuItem: View {
    let icon: String
    let title: String
    let disabled: Bool
    let action: () -> Void
    
    init(icon: String, title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.disabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(disabled ? .secondary : .accentColor)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(disabled ? .secondary : .primary)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
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
            showSettings: .constant(false),
            showShareOptions: .constant(false)
        )
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(DateRangeStore())
        .environment(SettingsStore())
    }
}
#endif
