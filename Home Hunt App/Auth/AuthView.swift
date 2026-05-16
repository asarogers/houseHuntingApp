import SwiftUI

struct AuthView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("HomeHunt").font(.largeTitle).bold()
            Text("Find a home together.").foregroundStyle(.secondary)
            Spacer()

            Button {
                Task { await auth.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.title2)
                    Text(auth.signingIn ? "Signing in…" : "Continue with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.signingIn)

            if let err = auth.error {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }
}
