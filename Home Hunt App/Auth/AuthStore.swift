import Foundation
import Combine
import Supabase
import GoogleSignIn
import UIKit

@MainActor
final class AuthStore: ObservableObject {
    @Published var session: Session?
    @Published var error: String?
    @Published var signingIn = false

    func bootstrap() async {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: AppConfig.googleIOSClientID,
            serverClientID: AppConfig.googleWebClientID
        )
        for await change in Supa.client.auth.authStateChanges {
            self.session = change.session
        }
    }

    func signInWithGoogle() async {
        signingIn = true; error = nil
        defer { signingIn = false }
        do {
            guard let presenter = Self.topViewController() else {
                error = "No window available"
                return
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                error = "Google did not return an ID token"
                return
            }
            let accessToken = result.user.accessToken.tokenString
            _ = try await Supa.client.auth.signInWithIdToken(
                credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        try? await Supa.client.auth.signOut()
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let root = scene?.keyWindow?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
