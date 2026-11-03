//
//  TowerUpgradePanel.swift
//  2DGame
//
//  Created by Adam Yang on 11/3/26.
//

import SpriteKit
import UIKit

final class TowerUpgradePanel: SKNode {

    enum Action {
        case close
        case upgrade(UpgradePath)
    }

    private let panel = SKSpriteNode(
        color: UIColor(white: 0.12, alpha: 1),
        size: .zero
    )

    private let closeButton = SKSpriteNode(
        color: .systemGray,
        size: CGSize(width: 70, height: 30)
    )

    private var upgradeButtons: [UpgradePath: SKSpriteNode] = [:]

    init(
        size: CGSize,
        tower: TowerManager.PlacedTower,
        money: Int
    ) {
        super.init()

        zPosition = 2_000

        let shade = SKSpriteNode(
            color: UIColor.black.withAlphaComponent(0.7),
            size: size
        )
        shade.anchorPoint = .zero
        addChild(shade)

        let width = min(620, size.width - 24)

        panel.size = CGSize(width: width, height: 280)
        panel.position = CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )
        panel.zPosition = 1
        addChild(panel)

        addLabel(
            "\(tower.type.displayName) Upgrades · $\(money)",
            x: -width / 2 + 16,
            y: 116,
            size: 18
        )

        addLabel(
            "First purchase locks this tower to that path.",
            x: -width / 2 + 16,
            y: 90,
            size: 12
        )

        closeButton.position = CGPoint(
            x: width / 2 - 48,
            y: 116
        )
        panel.addChild(closeButton)

        let closeText = SKLabelNode(fontNamed: "AvenirNext-Bold")
        closeText.text = "Close"
        closeText.fontSize = 13
        closeText.verticalAlignmentMode = .center
        closeButton.addChild(closeText)

        for (column, path) in UpgradePath.allCases.enumerated() {
            let definition = tower.type.upgradeDefinition(for: path)
            let x = -width / 2 + 16 + CGFloat(column) * width / 2

            let locked = tower.upgradePath != nil
                && tower.upgradePath != path

            let currentTier = tower.upgradePath == path
                ? tower.upgradeTier : 0

            addLabel(
                "\(definition.name) · Tier \(currentTier)/\(definition.tiers.count)",
                x: x,
                y: 57,
                size: 15
            )

            for (index, tier) in definition.tiers.enumerated() {
                let description = Self.describe(tier)
                let purchased = index < currentTier ? " ✓" : ""

                addLabel(
                    "Tier \(index + 1)\(purchased) · $\(tier.cost)\n\(description)",
                    x: x,
                    y: 20 - CGFloat(index) * 54,
                    size: 12,
                    width: width / 2 - 28
                )
            }

            let button = SKSpriteNode(
                color: .systemGreen,
                size: CGSize(width: width / 2 - 32, height: 36)
            )
            button.position = CGPoint(
                x: x + button.size.width / 2,
                y: -106
            )
            panel.addChild(button)

            let text: String

            if locked {
                text = "Other path locked"
                button.color = .darkGray
            } else if currentTier >= definition.tiers.count {
                text = "Fully upgraded"
                button.color = .darkGray
            } else {
                let cost = definition.tiers[currentTier].cost

                if money >= cost {
                    text = "Buy Tier \(currentTier + 1) · $\(cost)"
                    upgradeButtons[path] = button
                } else {
                    text = "Need $\(cost - money) more"
                    button.color = .darkGray
                }
            }

            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.text = text
            label.fontSize = 13
            label.verticalAlignmentMode = .center
            button.addChild(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func action(at scenePoint: CGPoint) -> Action? {
        guard let scene else { return nil }

        let point = panel.convert(scenePoint, from: scene)

        if closeButton.contains(point) {
            return .close
        }

        for (path, button) in upgradeButtons {
            if button.contains(point) {
                return .upgrade(path)
            }
        }

        return nil
    }

    private func addLabel(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        width: CGFloat = 0
    ) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
        label.text = text
        label.fontSize = size
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = width
        label.position = CGPoint(x: x, y: y)
        panel.addChild(label)
    }

    private static func describe(_ tier: TowerUpgradeTier) -> String {
        var changes: [String] = []

        if tier.damageIncrease > 0 {
            changes.append("+\(tier.damageIncrease) damage")
        }

        if tier.rangeIncrease > 0 {
            changes.append("+\(Int(tier.rangeIncrease)) range")
        }

        if tier.fireIntervalReduction > 0 {
            changes.append(
                String(
                    format: "−%.2fs shot interval",
                    tier.fireIntervalReduction
                )
            )
        }

        if tier.slowDurationIncrease > 0 {
            changes.append(
                String(
                    format: "+%.1fs slow duration",
                    tier.slowDurationIncrease
                )
            )
        }

        return changes.joined(separator: ", ")
    }
}
