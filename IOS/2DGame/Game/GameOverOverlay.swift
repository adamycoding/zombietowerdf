//
//  GameOverOverlay.swift
//  Game
//
//  MH2D-81: the Game Over screen — dimmed background, title and waves
//  survived. MH2D-82: Retry and Main Menu buttons. The Main Menu button only
//  appears when the menu exists (MH2D-22): pass `showsMainMenu: true`.
//

import SpriteKit
import UIKit

final class GameOverOverlay: SKNode {

    static let nodeName = "gameOverOverlay"

    enum Action {
        case retry
        case mainMenu
    }

    private let retryButton: SKShapeNode
    private let mainMenuButton: SKShapeNode?

    init(size: CGSize, wavesSurvived: Int, totalWaves: Int, showsMainMenu: Bool) {
        retryButton = GameOverOverlay.makeButton(title: "Retry", color: .systemGreen)
        mainMenuButton = showsMainMenu
            ? GameOverOverlay.makeButton(title: "Main Menu", color: .systemBlue)
            : nil
        super.init()
        name = GameOverOverlay.nodeName
        zPosition = Layer.hud.rawValue + 10

        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.7), size: size)
        dim.anchorPoint = .zero
        addChild(dim)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let title = makeLabel("GAME OVER", font: "AvenirNext-Bold", fontSize: 44, color: .systemRed)
        title.position = CGPoint(x: center.x, y: center.y + 50)
        addChild(title)

        let waves = makeLabel("Waves survived: \(wavesSurvived) / \(totalWaves)",
                              font: "AvenirNext-DemiBold", fontSize: 20, color: .white)
        waves.position = CGPoint(x: center.x, y: center.y + 12)
        addChild(waves)

        // Buttons side by side (or centered when there is only Retry).
        let buttonY = center.y - 40
        if let menu = mainMenuButton {
            retryButton.position = CGPoint(x: center.x - 80, y: buttonY)
            menu.position = CGPoint(x: center.x + 80, y: buttonY)
            addChild(menu)
        } else {
            retryButton.position = CGPoint(x: center.x, y: buttonY)
        }
        addChild(retryButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Which button (if any) is at this point in the scene's coordinates.
    func action(at scenePoint: CGPoint) -> Action? {
        let p = convert(scenePoint, from: parent ?? self)
        if hits(retryButton, p) { return .retry }
        if let menu = mainMenuButton, hits(menu, p) { return .mainMenu }
        return nil
    }

    private func hits(_ button: SKShapeNode, _ point: CGPoint) -> Bool {
        button.frame.insetBy(dx: -6, dy: -6).contains(point)
    }

    private static func makeButton(title: String, color: UIColor) -> SKShapeNode {
        let size = CGSize(width: 140, height: 44)
        let button = SKShapeNode(rectOf: size, cornerRadius: 10)
        button.fillColor = color.withAlphaComponent(0.85)
        button.strokeColor = .white
        button.lineWidth = 2
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = title
        label.fontSize = 20
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        button.addChild(label)
        return button
    }

    private func makeLabel(_ text: String, font: String, fontSize: CGFloat, color: UIColor) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: font)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }
}
