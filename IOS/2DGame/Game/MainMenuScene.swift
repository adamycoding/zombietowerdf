//
//  MainMenuScene.swift
//  Game
//
//  MH2D-22: the main menu (Play, Settings, How to Play, Credits) and the
//  map-select screen (MH2D-26). All drawn in code, like the rest of the game.
//

import SpriteKit
import UIKit

final class MainMenuScene: SKScene {

    /// Called with the map the player picked.
    var onPlayRequested: ((MapDefinition) -> Void)?

    private enum Page { case main, maps, settings, howToPlay, credits }
    private var page: Page = .main
    private let content = SKNode()

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.39, green: 0.49, blue: 0.25, alpha: 1)
        if content.parent == nil { addChild(content) }
        build()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard content.parent != nil else { return }
        build()
    }

    // MARK: Layout

    private func build() {
        content.removeAllChildren()
        guard size.width > 0, size.height > 0 else { return }
        switch page {
        case .main: buildMain()
        case .maps: buildMaps()
        case .settings: buildSettings()
        case .howToPlay:
            buildInfo(title: "How to Play", lines: [
                "Zombies walk the road toward your base.",
                "Drag a tower from the side panel onto the grass to build it.",
                "Tap a tower to upgrade it (3 tiers), change its Target, or sell it for 70% back.",
                "You earn money for kills and a bonus after every wave.",
                "If 150 zombies reach the base, it's over. Survive 40 waves to win.",
                "Maps with more roads split each wave between the roads. Use 1.5x to speed things up."
            ])
        case .credits:
            buildInfo(title: "Credits", lines: [
                "Zombie Tower Defense",
                "Made by Jon Russo and Adam",
                "Built with SpriteKit"
            ])
        }
    }

    private func title(_ text: String, y: CGFloat, fontSize: CGFloat = 40) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = .white
        label.position = CGPoint(x: size.width / 2, y: y)
        label.verticalAlignmentMode = .center
        content.addChild(label)
    }

    private func button(_ text: String, name: String, center: CGPoint,
                        size buttonSize: CGSize, color: UIColor) {
        let node = SKShapeNode(rectOf: buttonSize, cornerRadius: 10)
        node.name = "btn:" + name
        node.position = center
        node.fillColor = color
        node.strokeColor = .white
        node.lineWidth = 2
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 20
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        node.addChild(label)
        content.addChild(node)
    }

    private func buildMain() {
        title("ZOMBIE TOWER DEFENSE", y: size.height * 0.80, fontSize: min(40, size.width / 16))
        let names = [("Play", "play", UIColor.systemGreen),
                     ("Settings", "settings", UIColor.systemGray),
                     ("How to Play", "how", UIColor.systemBlue),
                     ("Credits", "credits", UIColor.systemPurple)]
        let spacing = min(64, size.height * 0.16)
        for (i, item) in names.enumerated() {
            button(item.0, name: item.1,
                   center: CGPoint(x: size.width / 2, y: size.height * 0.58 - CGFloat(i) * spacing),
                   size: CGSize(width: 240, height: 48), color: item.2)
        }
    }

    private func buildMaps() {
        title("Choose a Map", y: size.height - 34, fontSize: 28)
        button("Back", name: "back", center: CGPoint(x: 60, y: size.height - 34),
               size: CGSize(width: 90, height: 36), color: .systemGray)

        let maps = MapDefinition.all
        let columns = 3
        let rows = (maps.count + columns - 1) / columns
        let gap: CGFloat = 12
        let topY = size.height - 70
        let availableHeight = topY - 14
        let cardH = min(160, (availableHeight - gap * CGFloat(rows - 1)) / CGFloat(rows))
        let cardW = min(230, (size.width - 40 - gap * CGFloat(columns - 1)) / CGFloat(columns))
        let totalW = cardW * CGFloat(columns) + gap * CGFloat(columns - 1)
        let startX = (size.width - totalW) / 2 + cardW / 2

        for (i, map) in maps.enumerated() {
            let col = i % columns, row = i / columns
            let center = CGPoint(x: startX + CGFloat(col) * (cardW + gap),
                                 y: topY - cardH / 2 - CGFloat(row) * (cardH + gap))
            content.addChild(mapCard(map, index: i, size: CGSize(width: cardW, height: cardH), at: center))
        }
    }

    private func difficultyColor(_ d: MapDefinition.Difficulty) -> UIColor {
        switch d {
        case .beginner: return .systemGreen
        case .intermediate: return .systemYellow
        case .hard: return .systemRed
        }
    }

    private func mapCard(_ map: MapDefinition, index: Int, size: CGSize, at center: CGPoint) -> SKNode {
        let card = SKShapeNode(rectOf: size, cornerRadius: 10)
        card.name = "btn:map\(index)"
        card.position = center
        card.fillColor = SKColor(red: 0.16, green: 0.22, blue: 0.12, alpha: 0.92)
        card.strokeColor = difficultyColor(map.difficulty)
        card.lineWidth = 3

        // Little picture of the roads.
        let previewSize = CGSize(width: size.width - 20, height: size.height * 0.52)
        let previewTop = size.height / 2 - 8
        let bg = SKShapeNode(rectOf: previewSize, cornerRadius: 6)
        bg.fillColor = SKColor(red: 0.39, green: 0.49, blue: 0.25, alpha: 1)
        bg.strokeColor = .clear
        bg.position = CGPoint(x: 0, y: previewTop - previewSize.height / 2)
        card.addChild(bg)

        // The real map, drawn with the game's own map code (fitted inside the preview box).
        bg.fillColor = map.theme.ground
        if let texture = MapPreview.texture(for: map) {
            let scale = min(previewSize.width / MapPreview.size.width, previewSize.height / MapPreview.size.height)
            let picture = SKSpriteNode(texture: texture, size: CGSize(width: MapPreview.size.width * scale,
                                                                       height: MapPreview.size.height * scale))
            bg.addChild(picture)
        }

        let name = SKLabelNode(fontNamed: "AvenirNext-Bold")
        name.text = map.name
        name.fontSize = 16
        name.fontColor = .white
        name.verticalAlignmentMode = .center
        name.position = CGPoint(x: 0, y: -size.height / 2 + 44)
        card.addChild(name)

        let info = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        info.text = "\(map.difficulty.rawValue) · \(map.laneCount) road\(map.laneCount == 1 ? "" : "s")"
        info.fontSize = 12
        info.fontColor = difficultyColor(map.difficulty)
        info.verticalAlignmentMode = .center
        info.position = CGPoint(x: 0, y: -size.height / 2 + 26)
        card.addChild(info)

        let blurb = SKLabelNode(fontNamed: "AvenirNext-Regular")
        blurb.text = map.blurb
        blurb.fontSize = 9
        blurb.fontColor = SKColor(white: 0.85, alpha: 1)
        blurb.verticalAlignmentMode = .center
        blurb.position = CGPoint(x: 0, y: -size.height / 2 + 10)
        // Shrink long text to fit the card.
        let maxWidth = size.width - 12
        if blurb.frame.width > maxWidth { blurb.fontSize *= maxWidth / blurb.frame.width }
        card.addChild(blurb)
        return card
    }

    private func buildSettings() {
        title("Settings", y: size.height - 40, fontSize: 30)
        button("Back", name: "back", center: CGPoint(x: 60, y: size.height - 40),
               size: CGSize(width: 90, height: 36), color: .systemGray)
        let sound = SoundManager.shared
        button("Sound effects: \(sound.soundOn ? "ON" : "OFF")", name: "sound",
               center: CGPoint(x: size.width / 2, y: size.height * 0.70),
               size: CGSize(width: 300, height: 48), color: sound.soundOn ? .systemGreen : .systemGray)
        button("Zombie death sound: \(sound.deathSoundOn ? "ON" : "OFF")", name: "death",
               center: CGPoint(x: size.width / 2, y: size.height * 0.55),
               size: CGSize(width: 300, height: 48), color: sound.deathSoundOn ? .systemGreen : .systemGray)
        button("Music: \(sound.musicOn ? "ON" : "OFF")", name: "music",
               center: CGPoint(x: size.width / 2, y: size.height * 0.40),
               size: CGSize(width: 300, height: 48), color: sound.musicOn ? .systemGreen : .systemGray)
        button("Show hitboxes: \(DebugOverlay.showHitboxes ? "ON" : "OFF")", name: "hitboxes",
               center: CGPoint(x: size.width / 2, y: size.height * 0.25),
               size: CGSize(width: 300, height: 48), color: DebugOverlay.showHitboxes ? .systemGreen : .systemGray)
        let note = SKLabelNode(fontNamed: "AvenirNext-Regular")
        note.text = "Hitboxes are for testing."
        note.fontSize = 14
        note.fontColor = .white
        note.position = CGPoint(x: size.width / 2, y: size.height * 0.11)
        content.addChild(note)
    }

    private func buildInfo(title text: String, lines: [String]) {
        title(text, y: size.height - 40, fontSize: 30)
        button("Back", name: "back", center: CGPoint(x: 60, y: size.height - 40),
               size: CGSize(width: 90, height: 36), color: .systemGray)
        let lineHeight: CGFloat = 30
        var y = size.height * 0.68
        for line in lines {
            let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
            label.text = line
            label.fontSize = 16
            label.fontColor = .white
            label.position = CGPoint(x: size.width / 2, y: y)
            let maxWidth = size.width - 40
            if label.frame.width > maxWidth { label.fontSize *= maxWidth / label.frame.width }
            content.addChild(label)
            y -= lineHeight
        }
    }

    // MARK: Touch

    private func buttonName(at point: CGPoint) -> String? {
        for node in nodes(at: point) {
            var current: SKNode? = node
            while let n = current {
                if let name = n.name, name.hasPrefix("btn:") { return String(name.dropFirst(4)) }
                current = n.parent
            }
        }
        return nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let name = buttonName(at: touch.location(in: self)) else { return }
        SoundManager.shared.play(.tap)
        switch name {
        case "play": page = .maps
        case "settings": page = .settings
        case "how": page = .howToPlay
        case "credits": page = .credits
        case "back": page = (page == .maps || page == .settings || page == .howToPlay || page == .credits) ? .main : page
        case "sound": SoundManager.shared.soundOn.toggle()
        case "death": SoundManager.shared.deathSoundOn.toggle()
        case "music": SoundManager.shared.musicOn.toggle()
        case "hitboxes": DebugOverlay.showHitboxes.toggle()
        default:
            if name.hasPrefix("map"), let index = Int(name.dropFirst(3)), MapDefinition.all.indices.contains(index) {
                onPlayRequested?(MapDefinition.all[index])
                return
            }
        }
        build()
    }
}
