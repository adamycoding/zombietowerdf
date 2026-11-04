//
//  PauseOverlay.swift
//  Game
//
//  The pause menu: dimmed background with Resume, Restart and Main Menu.
//

import SpriteKit
import UIKit

final class PauseOverlay: SKNode {

    enum Action {
        case resume
        case restart
        case mainMenu
        case toggleSound
        case toggleMusic
    }

    private let buttons: [(Action, SKShapeNode)]
    private let soundButton = PauseOverlay.makeButton(title: "", color: .systemGray, width: 120)
    private let musicButton = PauseOverlay.makeButton(title: "", color: .systemGray, width: 120)

    init(size: CGSize) {
        buttons = [
            (.resume, PauseOverlay.makeButton(title: "Resume", color: .systemGreen)),
            (.restart, PauseOverlay.makeButton(title: "Restart", color: .systemOrange)),
            (.mainMenu, PauseOverlay.makeButton(title: "Main Menu", color: .systemBlue))
        ]
        super.init()
        name = "pauseOverlay"
        zPosition = 1000 // above every tower part (tower pieces reach z 120+)

        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.7), size: size)
        dim.anchorPoint = .zero
        addChild(dim)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "PAUSED"
        title.fontSize = 40
        title.fontColor = .white
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: center.x, y: center.y + 96)
        addChild(title)

        for (i, item) in buttons.enumerated() {
            item.1.position = CGPoint(x: center.x, y: center.y + 44 - CGFloat(i) * 52)
            addChild(item.1)
        }

        // Sound and music switches (the same settings as the main menu).
        soundButton.position = CGPoint(x: center.x - 66, y: center.y - 124)
        musicButton.position = CGPoint(x: center.x + 66, y: center.y - 124)
        addChild(soundButton)
        addChild(musicButton)
        refreshToggles()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Updates the two switch buttons to match the saved settings.
    func refreshToggles() {
        let sound = SoundManager.shared
        PauseOverlay.style(soundButton, title: "Sound: \(sound.soundOn ? "ON" : "OFF")", on: sound.soundOn)
        PauseOverlay.style(musicButton, title: "Music: \(sound.musicOn ? "ON" : "OFF")", on: sound.musicOn)
    }

    private static func style(_ button: SKShapeNode, title: String, on: Bool) {
        button.fillColor = (on ? UIColor.systemGreen : UIColor.systemGray).withAlphaComponent(0.85)
        (button.children.first as? SKLabelNode)?.text = title
    }

    func action(at scenePoint: CGPoint) -> Action? {
        let p = convert(scenePoint, from: parent ?? self)
        if soundButton.frame.insetBy(dx: -6, dy: -6).contains(p) { return .toggleSound }
        if musicButton.frame.insetBy(dx: -6, dy: -6).contains(p) { return .toggleMusic }
        for (action, button) in buttons where button.frame.insetBy(dx: -6, dy: -6).contains(p) {
            return action
        }
        return nil
    }

    private static func makeButton(title: String, color: UIColor, width: CGFloat = 180) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: width, height: 44), cornerRadius: 10)
        button.fillColor = color.withAlphaComponent(0.85)
        button.strokeColor = .white
        button.lineWidth = 2
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = title
        label.fontSize = width < 180 ? 16 : 20
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        button.addChild(label)
        return button
    }
}
