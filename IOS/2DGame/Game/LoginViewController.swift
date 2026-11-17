//
//  LoginViewController.swift
//  Game
//
//  MH2D-32: email/password sign-in and registration screen. Built in UIKit
//  (SpriteKit has no text fields) and presented full-screen over the game
//  until the player is signed in.
//

import UIKit

final class LoginViewController: UIViewController {

    /// Called after a successful sign-in or registration.
    var onAuthenticated: (() -> Void)?

    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let messageLabel = UILabel()
    private let signInButton = UIButton(type: .system)
    private let registerButton = UIButton(type: .system)
    private let googleButton = UIButton(type: .system)
    private let guestButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.39, green: 0.49, blue: 0.25, alpha: 1)

        let title = UILabel()
        title.text = "ZOMBIE TOWER DEFENSE"
        title.font = UIFont(name: "AvenirNext-Heavy", size: 26) ?? .boldSystemFont(ofSize: 26)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Sign in or create an account"
        subtitle.font = .systemFont(ofSize: 15, weight: .medium)
        subtitle.textColor = .white
        subtitle.textAlignment = .center

        configure(emailField, placeholder: "Email")
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .username
        emailField.returnKeyType = .next
        configure(passwordField, placeholder: "Password (6+ characters)")
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go

        style(signInButton, title: "Sign In", color: .systemGreen)
        style(registerButton, title: "Create Account", color: .systemBlue)
        style(googleButton, title: "Sign in with Google", color: .white)
        googleButton.setTitleColor(.black, for: .normal)
        googleButton.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)
        guestButton.setTitle("Continue as Guest", for: .normal)
        guestButton.setTitleColor(.white, for: .normal)
        guestButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        guestButton.addTarget(self, action: #selector(guestTapped), for: .touchUpInside)
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        registerButton.addTarget(self, action: #selector(registerTapped), for: .touchUpInside)

        messageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        messageLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0.85, alpha: 1)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2

        let buttons = UIStackView(arrangedSubviews: [signInButton, registerButton])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [title, subtitle, emailField, passwordField, buttons, googleButton, guestButton, messageLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 340)
        ])

        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:))))
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }

    // MARK: Helpers

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.backgroundColor = .white
        field.textColor = .black
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private func style(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.backgroundColor = color
        button.layer.cornerRadius = 10
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func setBusy(_ busy: Bool) {
        signInButton.isEnabled = !busy
        registerButton.isEnabled = !busy
        googleButton.isEnabled = !busy
        guestButton.isEnabled = !busy
        view.alpha = busy ? 0.8 : 1
    }

    private func credentials() -> (String, String)? {
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespaces)
        let password = passwordField.text ?? ""
        guard !email.isEmpty, !password.isEmpty else {
            messageLabel.text = "Enter your email and password."
            return nil
        }
        return (email, password)
    }

    private func finish(_ error: String?) {
        setBusy(false)
        if error == "cancelled" { messageLabel.text = nil; return }
        if let error { messageLabel.text = error; return }
        messageLabel.text = nil
        onAuthenticated?()
    }

    @objc private func signInTapped() {
        guard let (email, password) = credentials() else { return }
        view.endEditing(true)
        setBusy(true)
        AuthManager.shared.signIn(email: email, password: password) { [weak self] in self?.finish($0) }
    }

    @objc private func guestTapped() {
        view.endEditing(true)
        AuthManager.shared.continueAsGuest()
        onAuthenticated?()
    }

    @objc private func googleTapped() {
        view.endEditing(true)
        setBusy(true)
        AuthManager.shared.signInWithGoogle(presenting: self) { [weak self] in self?.finish($0) }
    }

    @objc private func registerTapped() {
        guard let (email, password) = credentials() else { return }
        view.endEditing(true)
        setBusy(true)
        AuthManager.shared.register(email: email, password: password) { [weak self] in self?.finish($0) }
    }
}

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailField { passwordField.becomeFirstResponder() } else { signInTapped() }
        return true
    }
}
