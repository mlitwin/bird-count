import SwiftUI

/// User view containing user settings and account information
struct UserView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Placeholder content - will be implemented later
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                    
                    Text("User Settings")
                        .font(.title2.weight(.semibold))
                    
                    Text("User profile and settings will be implemented here")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.General.close.string) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    UserView()
}
