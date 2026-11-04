//
//  PlayerWallet.swift
//  Economy
//
//  Owns the player's money: the starting amount, earning (kill rewards,
//  selling towers) and spending (buying towers). Everything else asks the
//  wallet instead of changing a number directly, and `onChange` tells the
//  UI to redraw.
//
//  MH2D-16 (Currency system) can grow this: wave bonuses, upgrade costs, etc.
//

import Foundation

final class PlayerWallet {

    /// Money the player starts a game with.
    static let startingMoney = 250

    private(set) var money: Int

    /// Called after every change with the new total.
    var onChange: ((Int) -> Void)?

    init(money: Int = PlayerWallet.startingMoney) {
        self.money = money
    }

    func canAfford(_ cost: Int) -> Bool {
        money >= cost
    }

    /// Adds money (never negative).
    func add(_ amount: Int) {
        guard amount > 0 else { return }
        money += amount
        onChange?(money)
    }

    /// Takes `cost` from the wallet. Returns false (and changes nothing) if
    /// the player can't afford it.
    @discardableResult
    func spend(_ cost: Int) -> Bool {
        guard cost >= 0, canAfford(cost) else { return false }
        money -= cost
        onChange?(money)
        return true
    }

    /// Sets the total directly (used by the `updatePlayerMoney` hook).
    func set(_ amount: Int) {
        money = max(0, amount)
        onChange?(money)
    }
}
