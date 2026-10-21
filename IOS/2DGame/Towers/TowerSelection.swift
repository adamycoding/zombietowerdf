//
//  TowerSelection.swift
//  2DGame
//
//  Created by Adam Yang on 9/30/26.
//

// Sample tower catalog. Replace these values with your team's agreed towers.
// This file contains game rules, not drawing code.

enum TowerType: String, CaseIterable {
    case soldier, sniper, ice

    var displayName: String {
        switch self {
        case .soldier: return "Soldier"
        case .sniper: return "Sniper"
        case .ice: return "Ice"
        }
    }

    var cost: Int {
        switch self {
        case .soldier: return 100
        case .sniper: return 200
        case .ice: return 300
        }
    }

    var symbolName: String {
        switch self {
        case .soldier: return "shield.fill"
        case .sniper: return "scope"
        case .ice: return "snowflake"
        }
    }
}

struct TowerSelectionState {
    private(set) var money: Int
    private(set) var unlockedTowers: [TowerType]
    private(set) var selectedTower: TowerType?

    // An optional stores either a selected tower or nil (no selection).
    var isPlacementMode: Bool { selectedTower != nil }

    init(money: Int, unlockedTowers: [TowerType]) {
        self.money = max(0, money)
        self.unlockedTowers = TowerType.allCases.filter { unlockedTowers.contains($0) }
    }

    func canSelect(_ tower: TowerType) -> Bool {
        unlockedTowers.contains(tower) && money >= tower.cost
    }

    @discardableResult
    mutating func select(_ tower: TowerType) -> Bool {
        guard canSelect(tower) else { return false }
        selectedTower = tower
        return true
    }

    mutating func cancel() {
        selectedTower = nil
    }

    mutating func updateMoney(_ newAmount: Int) {
        money = max(0, newAmount)
        validateSelection()
    }

    mutating func updateUnlockedTowers(_ towers: [TowerType]) {
        unlockedTowers = TowerType.allCases.filter { towers.contains($0) }
        validateSelection()
    }

    private mutating func validateSelection() {
        if let tower = selectedTower, !canSelect(tower) {
            cancel()
        }
    }
}

