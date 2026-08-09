import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(CloudAuthService.self) private var cloudAuth
    @State private var emailText: String = ""
    @State private var signInError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.tint)

                        Text("Account")
                            .font(.title2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section(Strings.User.email.string) {
                    TextField(Strings.User.emailPlaceholder.string, text: $emailText)
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

                Section("Apple ID") {
                    if cloudAuth.isSignedIn {
                        HStack {
                            Text("Account")
                            Spacer()
                            Text(cloudAuth.accountEmail ?? "Signed in")
                                .foregroundStyle(.secondary)
                        }
                        Button("Sign out", role: .destructive) { cloudAuth.signOut() }
                    } else {
                        Button("Sign in with Apple") {
                            signInError = nil
                            Task {
                                do { try await cloudAuth.signIn() }
                                catch { signInError = error.localizedDescription }
                            }
                        }
                        if let signInError {
                            Text(signInError).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
            }
            .onAppear {
                emailText = settingsStore.loginEmail
            }
            .navigationTitle("Account")
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
    let auth = CloudAuthService()
    let settings = SettingsStore()
    return AccountView()
        .environment(settings)
        .environment(auth)
}
