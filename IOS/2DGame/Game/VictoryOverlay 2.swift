//
//  VictoryOverlay.swift
//  Game
//
//  The win screen shown after the last wave is cleared: dimmed background,
//  title, a short summary and two buttons. Continue keeps playing (the waves
//  keep coming past the last one); Main Menu goes back to the menu. Like the
//  Game Over screen, the Main Menu button only appears when the menu exists
//  (pass `showsMainMenu: true`).
//

import SpriteKit
import UIKit

final class VictoryOverlay: SKNode {

    static let nodeName = "victoryOverlay"

    enum Action {
        case continuePlaying
        case mainMenu
    }

    private let continueButton: SKShapeNode
    private let mainMenuButton: SKShapeNode?

    init(size: CGSize, totalWaves: Int, livesLeft: Int, showsMainMenu: Bool) {
        continueButton = VictoryOverlay.makeButton(title: "Continue", color: .systemGreen)
        mainMenuButton = showsMainMenu
            ? VictoryOverlay.makeButton(title: "Main Menu", color: .systemBlue)
            : nil
        super.init()
        name = VictoryOverlay.nodeName
        zPosition = 1000 // above every tower part (tower pieces reach z 120+)

        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.7), size: size)
        dim.anchorPoint = .zero
        addChild(dim)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let title = makeLabel("YOU WIN!", font: "AvenirNext-Bold", fontSize: 44, color: .systemYellow)
        title.position = CGPoint(x: center.x, y: center.y + 56)
        addChild(title)

        let waves = makeLabel("All \(totalWaves) waves survived", font: "AvenirNext-DemiBold", fontSize: 20, color: .white)
        waves.position = CGPoint(x: center.x, y: center.y + 18)
        addChild(waves)

        let lives = makeLabel("Lives left: \(livesLeft)", font: "AvenirNext-Medium", fontSize: 16, color: UIColor(white: 0.85, alpha: 1))
        lives.position = CGPoint(x: center.x, y: center.y - 8)
        addChild(lives)

        // Buttons side by side (or centered when there is only Continue).
        let buttonY = center.y - 60
        if let menu = mainMenuButton {
            continueButton.position = CGPoint(x: center.x - 80, y: buttonY)
            menu.position = CGPoint(x: center.x + 80, y: buttonY)
            addChild(menu)
        } else {
            continueButton.position = CGPoint(x: center.x, y: buttonY)
        }
        addChild(continueButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Which button (if any) is at this point in the scene's coordinates.
    func action(at scenePoint: CGPoint) -> Action? {
        let p = convert(scenePoint, from: parent ?? self)
        if hits(continueButton, p) { return .continuePlaying }
        if let menu = mainMenuButton, hits(menu, p) { return .mainMenu }
        return nil
    }

    private func hits(_ button: SKShapeNode, _ point: CGPoint) -> Bool {
        button.frame.insetBy(dx: -6, dy: -6).contains(point)
    }

    private static func makeButton(title: String, color: UIColor) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: 140, height: 44), cornerRadius: 10)
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
