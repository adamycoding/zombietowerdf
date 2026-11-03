//
//  WaveCompleteOverlay.swift
//  2DGame
//
//  Created by Adam Yang on 11/3/26.
//

import SpriteKit
import UIKit

final class WaveCompleteOverlay: SKNode {

    private let background = SKSpriteNode(
        color: UIColor.black.withAlphaComponent(0.65),
        size: .zero
    )

    private let panel = SKSpriteNode(
        color: UIColor(white: 0.12, alpha: 1),
        size: .zero
    )

    private let titleLabel = SKLabelNode(
        fontNamed: "AvenirNext-Bold"
    )

    private let rewardLabel = SKLabelNode(
        fontNamed: "AvenirNext-Medium"
    )

    private let nextButton = SKSpriteNode(
        color: .systemGreen,
        size: CGSize(width: 190, height: 48)
    )

    private let hasNextWave: Bool
    
    private(set) var isManagingTowers = false

    private let manageButton = SKSpriteNode(
        color: .systemBlue,
        size: CGSize(width: 160, height: 40)
    )

    init(
        size: CGSize,
        completedWave: Int,
        reward: Int,
        hasNextWave: Bool
    ) {
        self.hasNextWave = hasNextWave
        super.init()

        zPosition = 1_000

        background.anchorPoint = .zero
        addChild(background)

        panel.zPosition = 1
        addChild(panel)

        titleLabel.text = "Wave \(completedWave) Complete!"
        titleLabel.fontSize = 24
        titleLabel.fontColor = .white
        titleLabel.verticalAlignmentMode = .center
        panel.addChild(titleLabel)

        rewardLabel.text = "Completion bonus: +$\(reward)"
        rewardLabel.fontSize = 18
        rewardLabel.fontColor = .systemYellow
        rewardLabel.verticalAlignmentMode = .center
        panel.addChild(rewardLabel)

        nextButton.isHidden = !hasNextWave
        panel.addChild(nextButton)
        manageButton.isHidden = !hasNextWave
        panel.addChild(manageButton)

        let manageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        manageLabel.text = "Manage Towers"
        manageLabel.fontSize = 16
        manageLabel.fontColor = .white
        manageLabel.verticalAlignmentMode = .center
        manageButton.addChild(manageLabel)

        let buttonLabel = SKLabelNode(
            fontNamed: "AvenirNext-Bold"
        )
        buttonLabel.text = "Next Wave"
        buttonLabel.fontSize = 20
        buttonLabel.fontColor = .white
        buttonLabel.verticalAlignmentMode = .center
        nextButton.addChild(buttonLabel)

        if !hasNextWave {
            titleLabel.text = "All \(completedWave) Waves Complete!"
        }

        layout(size: size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layout(size: CGSize) {
        if isManagingTowers {
            background.isHidden = true
            titleLabel.isHidden = true
            rewardLabel.isHidden = true
            manageButton.isHidden = true

            panel.size = CGSize(width: 190, height: 48)
            panel.position = CGPoint(
                x: size.width / 2,
                y: size.height - 70
            )

            nextButton.size = panel.size
            nextButton.position = .zero
            return
        }
        background.size = size

        panel.size = CGSize(
            width: min(380, size.width - 32),
            height: min(220, size.height - 24)
        )
        panel.position = CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )

        titleLabel.position = CGPoint(x: 0, y: 65)
        titleLabel.preferredMaxLayoutWidth = panel.size.width - 24
        titleLabel.numberOfLines = 2

        rewardLabel.position = CGPoint(x: 0, y: 10)
        nextButton.size = CGSize(width: 160, height: 40)
        nextButton.position = CGPoint(x: 88, y: -60)
        manageButton.position = CGPoint(x: -88, y: -60)
    }

    func isNextWaveTapped(at scenePoint: CGPoint) -> Bool {
        guard hasNextWave, let scene else {
            return false
        }

        let localPoint = panel.convert(scenePoint, from: scene)
        return nextButton.contains(localPoint)
    }
    
    func isManageTowersTapped(at scenePoint: CGPoint) -> Bool {
        guard hasNextWave,
              !isManagingTowers,
              let scene else {
            return false
        }

        let localPoint = panel.convert(scenePoint, from: scene)
        return manageButton.contains(localPoint)
    }

    func beginManagingTowers() {
        guard let scene else { return }

        isManagingTowers = true
        layout(size: scene.size)
    }
}
