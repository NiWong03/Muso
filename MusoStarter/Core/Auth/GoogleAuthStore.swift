import Foundation
import Combine
import UIKit
import GoogleSignIn

@MainActor
final class GoogleAuthStore: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var displayName = ""
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    var isSignedIn: Bool { userID != nil }
    private let scope = "https://www.googleapis.com/auth/youtube.readonly"
    private var generation = UUID()

    func restore() async {
        guard configure(), GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        let request = generation
        isBusy = true
        defer { isBusy = false }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            guard generation == request else { return }
            accept(user)
        } catch { /* Expired/revoked sessions remain signed out. */ }
    }

    func signIn() async {
        guard !isBusy else { return }
        guard configure() else {
            errorMessage = "Google sign-in is not configured in this build yet."
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: [scope])
            guard result.user.grantedScopes?.contains(scope) == true else {
                errorMessage = "Allow read-only YouTube access to connect your liked music."
                GIDSignIn.sharedInstance.signOut()
                return
            }
            accept(result.user)
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue { errorMessage = error.localizedDescription }
        }
    }

    func accessToken() async throws -> String? {
        guard isSignedIn else { return nil }
        let request = generation
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw AuthError.expired }
        do {
            let refreshed = try await user.refreshTokensIfNeeded()
            guard generation == request, refreshed.userID == userID else { throw CancellationError() }
            guard refreshed.grantedScopes?.contains(scope) == true else { throw AuthError.expired }
            return refreshed.accessToken.tokenString
        } catch is CancellationError { throw CancellationError() }
        catch { throw AuthError.expired }
    }

    func signOut() {
        generation = UUID()
        GIDSignIn.sharedInstance.signOut()
        userID = nil
        displayName = ""
        errorMessage = nil
    }

    func disconnect() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await GIDSignIn.sharedInstance.disconnect(); signOut() }
        catch { errorMessage = "Could not disconnect Google. Please try again." }
    }

    private func configure() -> Bool {
        guard let clientID = GoogleConfiguration.clientID else { return false }
        let expectedScheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        guard types.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains(expectedScheme) == true }) else { return false }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        return true
    }
    private func accept(_ user: GIDGoogleUser) {
        guard user.grantedScopes?.contains(scope) == true else { return }
        userID = user.userID
        displayName = user.profile?.givenName ?? "Listener"
    }
    enum AuthError: LocalizedError {
        case expired
        var errorDescription: String? { "Your Google session needs attention. Sign out and sign in again." }
    }
}
