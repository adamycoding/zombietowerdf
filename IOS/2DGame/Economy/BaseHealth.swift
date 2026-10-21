//
//  BaseHealth.swift
//  Economy
//
//  Owns the player's base health (lives). Zombies that reach the end of the
//  path take health away (MH2D-56). `onChange` tells the HUD to redraw
//  (MH2D-126 / MH2D-23), and `onDepleted` fires once when health hits 0 so
//  MH2D-57 can show Game Over.
//

import Foundation

final class BaseHealth {

    /// Health the base starts a game with.
    static let startingHealth = 5

    let maxHealth: Int
    private(set) var current: Int

    /// Called after every change with the new health.
    var onChange: ((Int) -> Void)?
    /// Called once, when health first reaches 0.
    var onDepleted: (() -> Void)?

    var isDepleted: Bool { current <= 0 }

    init(maxHealth: Int = BaseHealth.startingHealth) {
        self.maxHealth = maxHealth
        self.current = maxHealth
    }

    /// Take health away (never below 0). Does nothing once depleted.
    func damage(_ amount: Int = 1) {
        guard amount > 0, !isDepleted else { return }
        current = max(0, current - amount)
        onChange?(current)
        if isDepleted { onDepleted?() }
    }

    /// Put health back to full (used when a game restarts).
    func reset() {
        current = maxHealth
        onChange?(current)
    }
}
