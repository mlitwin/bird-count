import SwiftUI

/// User view containing user settings and account information
struct UserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @State private var emailText: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header section
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                    
                    Text("User Settings")
                        .font(.title2.weight(.semibold))
                }
                .padding(.top, 40)
                
                // Email section
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.User.email.string)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    TextField(Strings.User.emailPlaceholder.string, text: $emailText)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            settingsStore.loginEmail = emailText
                        }
                        .onChange(of: emailText) { _, newValue in
                            settingsStore.loginEmail = newValue
                        }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .onAppear {
                emailText = settingsStore.loginEmail
            }
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
        .environment(SettingsStore())
}
