//
//  GameScene.swift
//  ZombieTowerDefense
//
//  Sprint 1 — Game canvas & main loop
//  Covers subtasks:
//   MH2D-34  Set up project/engine scaffolding
//   MH2D-35  Implement render loop (draw each frame)
//   MH2D-36  Implement fixed-timestep update loop
//   MH2D-37  Handle app lifecycle (pause/resume/background)
//
//  SpriteKit already gives you the render loop and a variable-timestep
//  update loop for free (didMove/update(_:)). The main thing YOU build here
//  is (a) the scaffolding — scene setup, size, background, coordinate system —
//  and (b) a fixed-timestep accumulator on top of SpriteKit's update(_:),
//  so your gameplay logic (zombie movement, tower fire timers, wave timers)
//  ticks at a predictable rate regardless of frame-rate hitches. That
//  matters a lot for a tower defense game where fairness/determinism in
//  combat timing is part of the design.
//

import SpriteKit
import UIKit

final class GameScene: SKScene {

    // MARK: - MH2D-34: Scaffolding

    /// Root node everything gameplay-related gets added to. Keeping a
    /// single "world" node (instead of adding directly to the scene) makes
    /// it trivial to add camera panning/zooming later without touching
    /// every other piece of code.
    private let worldNode = SKNode()
    
    // Sample settings: adjust prices in TowerSelection.swift.
    private(set) var towerSelection = TowerSelectionState(
        money: 150,
        unlockedTowers: TowerType.allCases
    )
    private let towerPanel = SKSpriteNode(color: UIColor(white: 0.10, alpha: 1), size: .zero)
    private var towerCards: [(TowerType, SKShapeNode)] = []
    private var cancelButton: SKSpriteNode?
    private let selectionLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let placementPreview = SKNode()
    private var lastSafeArea: UIEdgeInsets = .zero

    /// Simple layering so towers/zombies/UI never fight over z-order.
    enum Layer: CGFloat {
        case background = 0
        case path = 10
        case towers = 20
        case zombies = 30
        case projectiles = 40
        case effects = 50
        case hud = 100
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Scaffolding: background, scaling, coordinate origin.
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.13, green: 0.16, blue: 0.13, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0) // origin at bottom-left; simplest for tile/grid math

        guard worldNode.parent == nil else {
            refreshTowerPanel()
            return
        }
        addChild(worldNode)
        setUpTowerPanel()

        setUpDebugStats(in: view) // remove once you trust the loop; handy while building it
        refreshTowerPanel()
        spawnZombie()
    }
    // MARK: - Tower selection panel (Adam)

    private func setUpTowerPanel() {
        towerPanel.anchorPoint = .zero
        towerPanel.zPosition = Layer.hud.rawValue
        addChild(towerPanel)

        selectionLabel.fontSize = 14
        selectionLabel.fontColor = .white
        selectionLabel.horizontalAlignmentMode = .left
        selectionLabel.zPosition = Layer.hud.rawValue
        addChild(selectionLabel)

        placementPreview.zPosition = Layer.effects.rawValue
        placementPreview.alpha = 0.65
        placementPreview.isHidden = true
        worldNode.addChild(placementPreview)
        refreshTowerPanel()
    }

    private func makeLabel(_ text: String, size: CGFloat = 14) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = size
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        return label
    }

    private func towerColor(_ tower: TowerType) -> UIColor {
        switch tower {
        case .soldier: return .systemGreen
        case .sniper: return .systemOrange
        case .ice: return .systemCyan
        }
    }

    private func towerIcon(_ tower: TowerType, enabled: Bool) -> SKSpriteNode {
        let color: UIColor = enabled ? towerColor(tower) : .lightGray
        let image = UIImage(systemName: tower.symbolName)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        let icon: SKSpriteNode
        if let image {
            icon = SKSpriteNode(texture: SKTexture(image: image))
        } else {
            icon = SKSpriteNode(color: color, size: CGSize(width: 24, height: 24))
        }
        icon.size = CGSize(width: 24, height: 24)
        icon.zPosition = 1
        return icon
    }

    // Rebuild only when money, unlocks, selection, or screen dimensions change.
    private func refreshTowerPanel() {
        guard towerPanel.parent != nil else { return }
        towerPanel.removeAllChildren()
        towerCards.removeAll()
        cancelButton = nil
        lastSafeArea = view?.safeAreaInsets ?? .zero

        let left = lastSafeArea.left + 16
        let right = lastSafeArea.right + 16
        let usableWidth = max(1, size.width - left - right)
        let gap: CGFloat = 8
        let cardHeight: CGFloat = 78
        let columns = max(1, min(4, Int((usableWidth + gap) / 128)))
        let towers = towerSelection.unlockedTowers
        let rows = max(1, (towers.count + columns - 1) / columns)
        let panelHeight = lastSafeArea.bottom + 16 + CGFloat(rows) * (cardHeight + gap) + 42
        towerPanel.size = CGSize(width: size.width, height: panelHeight)
        let cardWidth = (usableWidth - CGFloat(columns - 1) * gap) / CGFloat(columns)

        let heading = makeLabel("Towers · $\(towerSelection.money)", size: 16)
        heading.horizontalAlignmentMode = .left
        heading.position = CGPoint(x: left, y: panelHeight - 22)
        towerPanel.addChild(heading)

        if towerSelection.isPlacementMode {
            let cancel = SKSpriteNode(color: .darkGray, size: CGSize(width: 80, height: 36))
            cancel.position = CGPoint(x: size.width - right - 40, y: panelHeight - 22)
            cancel.addChild(makeLabel("Cancel"))
            towerPanel.addChild(cancel)
            cancelButton = cancel
        }

        for (index, tower) in towers.enumerated() {
            let enabled = towerSelection.canSelect(tower)
            let selected = towerSelection.selectedTower == tower
            let card = SKShapeNode(rectOf: CGSize(width: cardWidth, height: cardHeight), cornerRadius: 10)
            card.fillColor = enabled ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.14, alpha: 1)
            card.strokeColor = selected ? .systemYellow : UIColor(white: 0.35, alpha: 1)
            card.lineWidth = selected ? 3 : 1
            card.alpha = enabled ? 1 : 0.45
            card.position = CGPoint(
                x: left + cardWidth / 2 + CGFloat(index % columns) * (cardWidth + gap),
                y: panelHeight - 48 - cardHeight / 2 - CGFloat(index / columns) * (cardHeight + gap)
            )
            let icon = towerIcon(tower, enabled: enabled)
            icon.position = CGPoint(x: -cardWidth / 2 + 22, y: 14)
            card.addChild(icon)
            let name = makeLabel(tower.displayName, size: 14)
            name.horizontalAlignmentMode = .left
            name.position = CGPoint(x: -cardWidth / 2 + 42, y: 14)
            card.addChild(name)
            let price = makeLabel("$\(tower.cost)", size: 16)
            price.position = CGPoint(x: 0, y: -8)
            card.addChild(price)
            let status = makeLabel(enabled ? (selected ? "Selected" : "Select") : "Need $\(tower.cost - towerSelection.money)", size: 11)
            status.position = CGPoint(x: 0, y: -27)
            card.addChild(status)
            towerPanel.addChild(card)
            towerCards.append((tower, card))
        }

        if towers.isEmpty {
            let empty = makeLabel("No towers unlocked yet")
            empty.position = CGPoint(x: size.width / 2, y: lastSafeArea.bottom + 50)
            towerPanel.addChild(empty)
        }

        selectionLabel.position = CGPoint(x: left, y: panelHeight + 18)
        selectionLabel.text = towerSelection.selectedTower.map {
            "Placement mode: \($0.displayName) · preview only"
        } ?? "Choose an affordable tower"
        debugLabel?.position = CGPoint(x: left, y: size.height - lastSafeArea.top - 24)
        updatePlacementPreview()
        setUpPath()
    
    }
    //this will spawn zombies - Adam
    private func spawnZombie() {
        guard let startPoint = pathWaypoints.first else { return }

        let zombie = SKShapeNode(circleOfRadius: 12)
        zombie.name = "zombie"
        zombie.fillColor = .systemGreen
        zombie.strokeColor = .black
        zombie.lineWidth = 2
        zombie.position = startPoint
        zombie.zPosition = Layer.zombies.rawValue

        worldNode.addChild(zombie)
        zombies.append(ZombieState(node: zombie))
    } //Ends spawnZombie()
    
    private func moveZombie(deltaTime: TimeInterval) {
        // Work backward so removing a zombie doesn't shift
        // the indexes of zombies we still need to update.
        for index in zombies.indices.reversed() {
            let zombie = zombies[index].node
            var remainingMovement = zombieSpeed * CGFloat(deltaTime)

            while remainingMovement > 0 {
                let waypointIndex = zombies[index].nextWaypointIndex

                guard waypointIndex < pathWaypoints.count else {
                    zombie.removeFromParent()
                    zombies.remove(at: index)
                    break
                }

                let target = pathWaypoints[waypointIndex]
                let dx = target.x - zombie.position.x
                let dy = target.y - zombie.position.y
                let distance = (dx * dx + dy * dy).squareRoot()

                if distance <= remainingMovement {
                    zombie.position = target
                    remainingMovement -= distance
                    zombies[index].nextWaypointIndex += 1
                } else {
                    zombie.position.x += (dx / distance) * remainingMovement
                    zombie.position.y += (dy / distance) * remainingMovement
                    remainingMovement = 0
                }
            }
        }
    }

    // These are the connection points for a future money/unlock system.
    func updatePlayerMoney(_ amount: Int) {
        towerSelection.updateMoney(amount)
        refreshTowerPanel()
    }

    func updateUnlockedTowers(_ towers: [TowerType]) {
        towerSelection.updateUnlockedTowers(towers)
        refreshTowerPanel()
    }

    private func updatePlacementPreview() {
        placementPreview.removeAllChildren()
        guard let tower = towerSelection.selectedTower else {
            placementPreview.isHidden = true
            return
        }
        placementPreview.isHidden = false
        let outline = SKShapeNode(circleOfRadius: 22)
        outline.strokeColor = .systemYellow
        outline.lineWidth = 2
        placementPreview.addChild(outline)
        placementPreview.addChild(towerIcon(tower, enabled: true))
        placementPreview.position = CGPoint(x: size.width / 2, y: (towerPanel.size.height + size.height) / 2)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let panelPoint = touch.location(in: towerPanel)

        // Panel taps must not fall through to the map.
        if point.y <= towerPanel.size.height {
            if let cancel = cancelButton, cancel.contains(panelPoint) {
                towerSelection.cancel()
                refreshTowerPanel()
                return
            }
            for (tower, card) in towerCards where card.contains(panelPoint) {
                if towerSelection.select(tower) {
                    refreshTowerPanel()
                }
                return
            }
            return
        }
        movePlacementPreview(to: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        movePlacementPreview(to: touch.location(in: self))
    }

    private func movePlacementPreview(to point: CGPoint) {
        guard towerSelection.isPlacementMode,
              point.y > towerPanel.size.height + 24,
              point.y < size.height - lastSafeArea.top - 24,
              point.x > lastSafeArea.left + 24,
              point.x < size.width - lastSafeArea.right - 24 else { return }
        placementPreview.position = point
        // Actual placement, map validation, and payment belong to the next story.
        // That system can read towerSelection.selectedTower and this position.
    }

    // MARK: - MH2D-36: Fixed-timestep update loop

    /// Gameplay tick rate. 1/30 is a good default for a mobile tower
    /// defense — fine-grained enough for smooth movement, coarse enough to
    /// stay cheap on older devices. Change this in one place if you tune it.
    private let fixedTimestep: TimeInterval = 1.0 / 30.0

    private var accumulator: TimeInterval = 0
    private var lastUpdateTime: TimeInterval?

    /// SpriteKit calls this once per rendered frame (MH2D-35's render loop
    /// is SpriteKit's own — you don't write it, you hook into it here).
    /// `currentTime` is wall-clock time, not delta, so the first thing any
    /// SpriteKit update loop does is turn it into a delta.
    override func update(_ currentTime: TimeInterval) {
        if let view, view.safeAreaInsets != lastSafeArea {
            refreshTowerPanel()
        }
        defer { lastUpdateTime = currentTime }

        guard let last = lastUpdateTime else {
            // First frame: nothing to simulate yet, just record the timestamp.
            return
        }

        var frameDelta = currentTime - last

        // Guard against huge deltas (e.g. returning from background, or a
        // debugger breakpoint) so the game doesn't try to "catch up" by
        // simulating hundreds of ticks at once.
        frameDelta = min(frameDelta, 0.25)

        accumulator += frameDelta

        // Run gameplay logic at a fixed rate, possibly multiple times per
        // rendered frame (or zero times, if the device is rendering faster
        // than the tick rate).
        while accumulator >= fixedTimestep {
            tick(deltaTime: fixedTimestep)
            accumulator -= fixedTimestep
        }
    }

    /// This is where MH2D-7 (zombie movement), MH2D-9 (tower targeting),
    /// wave timers, etc. will eventually plug in. For Sprint 1 it just
    /// proves the loop runs at a stable, fixed rate.
    private func tick(deltaTime: TimeInterval) {
        spawnTimer += deltaTime

        while spawnTimer >= spawnInterval {
            spawnTimer -= spawnInterval
            spawnZombie()
        }

        moveZombie(deltaTime: deltaTime)

        tickCount += 1
        updateDebugStats()
    }
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        refreshTowerPanel()
    }
    // MARK: - MH2D-37: App lifecycle (pause/resume/background)

    /// Call these from your SKView-hosting view controller / SwiftUI
    /// `.onChange(of: scenePhase)` — see GameViewController.swift and
    /// ContentView.swift in this starter for the wiring.
    func handleAppDidEnterBackground() {
        isPaused = true
        // Reset the accumulator so we don't "fast-forward" the game when
        // we come back — otherwise a long background stay would dump a
        // huge backlog of ticks into the first foreground frame.
        accumulator = 0
        lastUpdateTime = nil
    }

    func handleAppWillEnterForeground() {
        isPaused = false
    }

    // MARK: - Debug HUD (temporary, delete once loop is verified)

    private var tickCount: Int = 0
    private var debugLabel: SKLabelNode?

    private func setUpDebugStats(in view: SKView) {
        view.showsFPS = true
        view.showsNodeCount = true

        let label = SKLabelNode(fontNamed: "Menlo")
        label.fontSize = 14
        label.fontColor = .green
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: 10, y: self.size.height - 40)
        label.zPosition = Layer.hud.rawValue
        addChild(label)
        debugLabel = label
    }

    private func updateDebugStats() {
        debugLabel?.text = "fixed ticks: \(tickCount)"
    }
    
    // Ordered points that zombies will follow - Adam
    private var pathWaypoints: [CGPoint] = []
    
    private struct ZombieState {
        let node: SKShapeNode
        var nextWaypointIndex: Int = 1
    }

    private var zombies: [ZombieState] = []
    private let zombieSpeed: CGFloat = 60

    private var spawnTimer: TimeInterval = 0
    private let spawnInterval: TimeInterval = 1.5
    
    private func setUpPath() {
        // Keep the route above the tower selection panel.
        let left = lastSafeArea.left + 40
        let right = size.width - lastSafeArea.right - 40
        let bottom = towerPanel.size.height + 60
        let top = size.height - lastSafeArea.top - 60

        guard right > left, top > bottom else { return }

        let middleX = (left + right) / 2
        let lowerY = bottom + (top - bottom) * 0.25
        let upperY = bottom + (top - bottom) * 0.75

        pathWaypoints = [
            CGPoint(x: left, y: lowerY),       // Start
            CGPoint(x: middleX, y: lowerY),    // Walk right
            CGPoint(x: middleX, y: upperY),    // Turn upward
            CGPoint(x: right, y: upperY)      // Walk right to the end
        ]

        // Draw the same route that zombies will eventually follow.
        worldNode.childNode(withName: "zombiePath")?.removeFromParent()

        let drawing = CGMutablePath()
        drawing.move(to: pathWaypoints[0])

        for waypoint in pathWaypoints.dropFirst() {
            drawing.addLine(to: waypoint)
        }

        let pathNode = SKShapeNode(path: drawing)
        pathNode.name = "zombiePath"
        pathNode.strokeColor = .brown
        pathNode.lineWidth = 32
        pathNode.zPosition = Layer.path.rawValue

        worldNode.addChild(pathNode)
    }
}
