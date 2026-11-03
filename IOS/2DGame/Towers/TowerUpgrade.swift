//
//  TowerUpgrade.swift
//  2DGame
//
//  Created by Adam Yang on 11/3/26.
//

import Foundation

enum UpgradePath: String, CaseIterable {
    case a
    case b
}

struct TowerUpgradeTier {
    let cost: Int

    // Changes added by purchasing this tier.
    let damageIncrease: Int
    let rangeIncrease: Double
    let fireIntervalReduction: Double
    let slowDurationIncrease: Double
}

struct TowerUpgradeDefinition {
    let name: String
    let tiers: [TowerUpgradeTier]
}

extension TowerType {

    func upgradeDefinition(
        for path: UpgradePath
    ) -> TowerUpgradeDefinition {
        switch (self, path) {

        case (.soldier, .a):
            return TowerUpgradeDefinition(
                name: "Rapid Fire",
                tiers: [
                    TowerUpgradeTier(
                        cost: 75,
                        damageIncrease: 0,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0.15,
                        slowDurationIncrease: 0
                    ),
                    TowerUpgradeTier(
                        cost: 125,
                        damageIncrease: 0,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0.15,
                        slowDurationIncrease: 0
                    )
                ]
            )

        case (.soldier, .b):
            return TowerUpgradeDefinition(
                name: "Heavy Rounds",
                tiers: [
                    TowerUpgradeTier(
                        cost: 100,
                        damageIncrease: 1,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 0
                    ),
                    TowerUpgradeTier(
                        cost: 175,
                        damageIncrease: 2,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 0
                    )
                ]
            )

        case (.sniper, .a):
            return TowerUpgradeDefinition(
                name: "Quick Reload",
                tiers: [
                    TowerUpgradeTier(
                        cost: 125,
                        damageIncrease: 0,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0.3,
                        slowDurationIncrease: 0
                    ),
                    TowerUpgradeTier(
                        cost: 200,
                        damageIncrease: 0,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0.3,
                        slowDurationIncrease: 0
                    )
                ]
            )

        case (.sniper, .b):
            return TowerUpgradeDefinition(
                name: "Longshot",
                tiers: [
                    TowerUpgradeTier(
                        cost: 150,
                        damageIncrease: 1,
                        rangeIncrease: 30,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 0
                    ),
                    TowerUpgradeTier(
                        cost: 250,
                        damageIncrease: 2,
                        rangeIncrease: 40,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 0
                    )
                ]
            )

        case (.ice, .a):
            return TowerUpgradeDefinition(
                name: "Wide Freeze",
                tiers: [
                    TowerUpgradeTier(
                        cost: 125,
                        damageIncrease: 0,
                        rangeIncrease: 20,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 0
                    ),
                    TowerUpgradeTier(
                        cost: 200,
                        damageIncrease: 0,
                        rangeIncrease: 25,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 0
                    )
                ]
            )

        case (.ice, .b):
            return TowerUpgradeDefinition(
                name: "Lasting Frost",
                tiers: [
                    TowerUpgradeTier(
                        cost: 125,
                        damageIncrease: 0,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 1
                    ),
                    TowerUpgradeTier(
                        cost: 200,
                        damageIncrease: 0,
                        rangeIncrease: 0,
                        fireIntervalReduction: 0,
                        slowDurationIncrease: 1
                    )
                ]
            )
        }
    }
}
