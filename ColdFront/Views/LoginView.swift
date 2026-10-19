import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var user = ""
    @State private var pass = ""
    @FocusState private var focus: Field?
    enum Field { case user, pass }

    var body: some View {
        ZStack {
            Theme.background(Color(red: 0.3, green: 0.7, blue: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Spacer(minLength: 60)
                    HStack(spacing: 10) {
                        Image(systemName: "snowflake").foregroundStyle(Color(red: 0.3, green: 0.7, blue: 1))
                        Image(systemName: "sun.max.fill").foregroundStyle(Color(red: 1, green: 0.55, blue: 0.25))
                    }
                    .font(.system(size: 40, weight: .light))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Equinox").font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Sign in with your ConnectLife account to control your air conditioner.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        TextField("Email", text: $user)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .user)
                            .submitLabel(.next)
                            .onSubmit { focus = .pass }
                            .padding(16)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        SecureField("Password", text: $pass)
                            .textContentType(.password)
                            .focused($focus, equals: .pass)
                            .submitLabel(.go)
                            .onSubmit(signIn)
                            .padding(16)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let e = store.error {
                        Text(e).font(.footnote).foregroundStyle(.red)
                    }

                    Button(action: signIn) {
                        HStack {
                            if store.busy { ProgressView().tint(.black) }
                            Text(store.busy ? "Signing in" : "Sign in").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.3, green: 0.7, blue: 1), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                    }
                    .disabled(store.busy || user.isEmpty || pass.isEmpty)

                    Text("Accounts created with Google or Apple sign-in won't work. In the official app, sign out, use \"Forgot password\" to set a password for your email, then use that here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
        .onAppear { user = store.savedUsername }
    }

    private func signIn() {
        focus = nil
        Task { await store.login(user: user.trimmingCharacters(in: .whitespaces), pass: pass) }
    }
}
