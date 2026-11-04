//
//  TowerSelection.swift
//  2DGame
//
//  Created by Adam Yang on 9/30/26.
//

// Sample tower catalog. Replace these values with your team's agreed towers.
// This file contains game rules, not drawing code.

enum TowerType: String, CaseIterable {
    case soldier, gunner, sniper, grenadier, flamethrower, tesla, trapper, ice

    var displayName: String {
        switch self {
        case .soldier: return "Turret"
        case .gunner: return "Gunner"
        case .sniper: return "Sniper"
        case .grenadier: return "Grenadier"
        case .flamethrower: return "Flamer"
        case .tesla: return "Tesla"
        case .trapper: return "Barbed Wire"
        case .ice: return "Ice"
        }
    }

    var cost: Int {
        switch self {
        case .soldier: return 100
        case .gunner: return 150
        case .sniper: return 200
        case .grenadier: return 250
        case .flamethrower: return 175
        case .tesla: return 350
        case .trapper: return 125
        case .ice: return 300
        }
    }

    var symbolName: String {
        switch self {
        case .soldier: return "shield.fill"
        case .gunner: return "bolt.fill"
        case .sniper: return "scope"
        case .grenadier: return "flame.fill"
        case .flamethrower: return "flame"
        case .tesla: return "bolt.circle.fill"
        case .trapper: return "xmark.shield.fill"
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

