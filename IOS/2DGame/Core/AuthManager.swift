//
//  AuthManager.swift
//  Core
//
//  MH2D-32: thin wrapper around Firebase Authentication (email/password).
//  Firebase keeps the signed-in user in the keychain, so auth state persists
//  across app restarts without logging in again.
//

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

final class AuthManager {

    static let shared = AuthManager()
    private init() {}

    var isSignedIn: Bool { Auth.auth().currentUser != nil }
    var currentEmail: String? { Auth.auth().currentUser?.email }

    func register(email: String, password: String, completion: @escaping (String?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { _, error in
            DispatchQueue.main.async { completion(error.map(AuthManager.message(for:))) }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (String?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            DispatchQueue.main.async { completion(error.map(AuthManager.message(for:))) }
        }
    }

    /// Google sign-in: shows Google's login sheet, then signs the Google
    /// account into Firebase. Completion gets nil on success, a message on
    /// failure, and also nil if the player simply cancelled.
    func signInWithGoogle(presenting: UIViewController, completion: @escaping (String?) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion("Google sign-in isn't set up (missing client ID).")
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { result, error in
            if let error {
                let cancelled = (error as NSError).code == GIDSignInError.canceled.rawValue
                DispatchQueue.main.async { completion(cancelled ? "cancelled" : AuthManager.message(for: error)) }
                return
            }
            guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                DispatchQueue.main.async { completion("Google sign-in failed.") }
                return
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: user.accessToken.tokenString)
            Auth.auth().signIn(with: credential) { _, error in
                DispatchQueue.main.async { completion(error.map(AuthManager.message(for:))) }
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    /// Turns Firebase error codes into short messages a player can read.
    private static func message(for error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidEmail: return "That email address isn't valid."
        case .emailAlreadyInUse: return "An account with that email already exists."
        case .weakPassword: return "Password must be at least 6 characters."
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "Email or password is incorrect."
        case .networkError: return "No internet connection."
        case .tooManyRequests: return "Too many attempts. Try again later."
        default: return error.localizedDescription
        }
    }
}
