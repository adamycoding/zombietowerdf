//
//  GameScene.swift
//  ZombieTowerDefense
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

    // MARK: Game systems
    //
    // GameScene only wires these together and handles input/UI. The rules
    // live in the managers (Map/, Zombies/, Towers/, Combat/).

    private lazy var path = GamePath(world: worldNode)
    private lazy var zombieManager = ZombieManager(world: worldNode, path: path)
    private lazy var projectileSystem = ProjectileSystem(world: worldNode, zombies: zombieManager, path: path)
    private lazy var towerManager = TowerManager(world: worldNode, path: path,
                                                 zombies: zombieManager, projectiles: projectileSystem)

    // Sample settings: adjust prices in TowerSelection.swift.
    private(set) var towerSelection = TowerSelectionState(
        money: 1000, // TEMP test value so you can place many towers; set back to ~150 later
        unlockedTowers: TowerType.allCases
    )

    // MARK: Tower panel / placement UI state
    private let towerPanel = SKSpriteNode(color: UIColor(white: 0.10, alpha: 1), size: .zero)
    private var towerCards: [(TowerType, SKShapeNode)] = []
    private var cancelButton: SKSpriteNode?
    private var sellButton: SKSpriteNode?
    private let selectionLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let placementPreview = SKNode()
    private var lastSafeArea: UIEdgeInsets = .zero
    private var previewOutline: SKShapeNode?
    /// True while a tower card is being dragged toward the map.
    private var isDraggingTower = false
    /// True when the current touch began on the Sell button.
    private var touchStartedOnSell = false
    /// Offset of the placement preview from the finger/cursor. Zero = the
    /// tower is centered exactly on the touch point (raise y to float it
    /// above a finger on a real phone).
    private let dragOffset = CGPoint(x: 0, y: 0)

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
        setUpHitboxDebugControls() // MH2D-12 test toggles (hitbox overlay, stress test)
        refreshTowerPanel()
        // First zombie now comes from tick()'s spawn timer, which waits for a valid path.
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

    // Rebuild only when money, unlocks, selection, or screen dimensions change.
    private func refreshTowerPanel() {
        guard towerPanel.parent != nil else { return }
        towerPanel.removeAllChildren()
        towerCards.removeAll()
        cancelButton = nil
        sellButton = nil
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

        // Tell the tower system where towers may be placed.
        towerManager.playfield = TowerManager.Playfield(
            minX: lastSafeArea.left + 24,
            maxX: size.width - lastSafeArea.right - 24,
            minY: panelHeight + 24,
            maxY: size.height - lastSafeArea.top - 24
        )

        let heading = makeLabel("Towers · $\(towerSelection.money)", size: 16)
        heading.horizontalAlignmentMode = .left
        heading.position = CGPoint(x: left, y: panelHeight - 22)
        towerPanel.addChild(heading)

        // (No Cancel button: placement is drag-and-drop, so releasing over
        // the panel cancels.)

        // Sell button: only while a placed tower is selected (never at the
        // same time as placement mode).
        if let selectedTower = towerManager.selected {
            let refund = TowerManager.sellValue(of: selectedTower.type)
            let sell = SKSpriteNode(color: .systemRed, size: CGSize(width: 130, height: 36))
            sell.position = CGPoint(x: size.width - right - 65, y: panelHeight - 22)
            sell.addChild(makeLabel("Sell +$\(refund)"))
            towerPanel.addChild(sell)
            sellButton = sell
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
            let icon = tower.makeIcon(enabled: enabled)
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
        if let tower = towerSelection.selectedTower {
            selectionLabel.text = "Drag to the map and release to place \(tower.displayName)"
        } else if let selectedTower = towerManager.selected {
            selectionLabel.text = "\(selectedTower.type.displayName) selected · tap Sell to remove it"
        } else {
            selectionLabel.text = "Drag a tower from the panel onto the map"
        }
        debugLabel?.position = CGPoint(x: left, y: size.height - lastSafeArea.top - 24)
        layoutDebugControls()
        updatePlacementPreview()
        setUpPath()
    }

    // MARK: - Map

    /// Builds (or re-fits) the zombie route above the tower panel.
    private func setUpPath() {
        let bounds = GamePath.Bounds(
            left: lastSafeArea.left + 40,
            right: size.width - lastSafeArea.right - 40,
            bottom: towerPanel.size.height + 60,
            top: size.height - lastSafeArea.top - 60
        )
        // If the route moved, put existing zombies at the same spot along it.
        if let oldWaypoints = path.rebuild(in: bounds) {
            zombieManager.remapProgress(from: oldWaypoints)
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
        let outline = SKShapeNode(circleOfRadius: TowerManager.radius)
        outline.strokeColor = .systemYellow
        outline.lineWidth = 2
        // Range radius of the tower being dragged.
        placementPreview.addChild(TowerVisuals.makeRangeRing(radius: tower.spec.range))
        placementPreview.addChild(outline)
        previewOutline = outline
        placementPreview.addChild(tower.makeIcon(enabled: true))
        placementPreview.position = CGPoint(x: size.width / 2, y: (towerPanel.size.height + size.height) / 2)
        updatePreviewValidity()
    }

    // MARK: - Touch handling (drag-and-drop placement)
    //
    // Press a tower card, drag onto the map, release to place. Releasing on
    // the panel or on a red (invalid) spot cancels with no money spent.
    // Sell fires when the finger lifts on the Sell button, not on touch-down.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let panelPoint = touch.location(in: towerPanel)
        isDraggingTower = false
        touchStartedOnSell = false

        // Panel touches must not fall through to the map.
        if point.y <= towerPanel.size.height {
            if let sell = sellButton, sell.contains(panelPoint) {
                touchStartedOnSell = true
                return
            }
            for (tower, card) in towerCards where card.contains(panelPoint) {
                if towerSelection.select(tower) { // false if it can't be afforded
                    towerManager.deselect()        // picking a card leaves "tower selected" mode
                    isDraggingTower = true
                    refreshTowerPanel()            // shows the preview
                    movePlacementPreview(to: point)
                }
                return
            }
            return
        }

        // MH2D-12 debug toggles (top-left of the map).
        if hitboxToggleLabel?.frame.insetBy(dx: -10, dy: -8).contains(point) == true {
            toggleHitboxes()
            return
        }
        if stressToggleLabel?.frame.insetBy(dx: -10, dy: -8).contains(point) == true {
            toggleStress()
            return
        }

        // Map touch: tapping a placed tower selects it, empty map deselects.
        if towerManager.select(at: point) {
            refreshTowerPanel()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDraggingTower, let touch = touches.first else { return }
        movePlacementPreview(to: touch.location(in: self))
    }

    /// Release: place the tower if the finger is over the map and the spot
    /// is valid; otherwise cancel the drag.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        if isDraggingTower {
            isDraggingTower = false
            let releasePoint = touch.location(in: self)
            // Use the final finger position, even if no "moved" events arrived.
            movePlacementPreview(to: releasePoint)
            if releasePoint.y > towerPanel.size.height {
                placeTower(at: placementPreview.position)
            }
            if towerSelection.isPlacementMode { // released on panel or invalid spot
                towerSelection.cancel()
                refreshTowerPanel()
            }
            return
        }

        if touchStartedOnSell {
            touchStartedOnSell = false
            if let sell = sellButton, sell.contains(touch.location(in: towerPanel)) {
                sellSelectedTower()
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStartedOnSell = false
        if isDraggingTower {
            isDraggingTower = false
            towerSelection.cancel()
            refreshTowerPanel()
        }
    }

    /// The preview follows the finger/cursor (plus dragOffset).
    private func movePlacementPreview(to touchPoint: CGPoint) {
        guard towerSelection.isPlacementMode else { return }
        placementPreview.position = CGPoint(x: touchPoint.x + dragOffset.x,
                                            y: touchPoint.y + dragOffset.y)
        updatePreviewValidity()
    }

    /// Green outline = can place here, red = can't.
    private func updatePreviewValidity() {
        previewOutline?.strokeColor = towerManager.isValidPlacement(at: placementPreview.position)
            ? .systemGreen : .systemRed
    }

    // MARK: - Buying and selling towers (money lives here; rules live in TowerManager)

    private func placeTower(at point: CGPoint) {
        guard let type = towerSelection.selectedTower,
              towerSelection.canSelect(type),
              towerManager.place(type, at: point) else { return } // rejected: nothing placed, no money spent

        // Pay, leave placement mode, and refresh the panel (money, card states).
        towerSelection.updateMoney(towerSelection.money - type.cost)
        towerSelection.cancel()
        refreshTowerPanel()
    }

    /// Remove the selected tower, refund part of its cost, free its spot.
    private func sellSelectedTower() {
        guard let type = towerManager.sellSelected() else { return }
        towerSelection.updateMoney(towerSelection.money + TowerManager.sellValue(of: type))
        refreshTowerPanel()
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

    /// One gameplay step. Order matters: spawn → move → towers fire →
    /// projectiles move and hit.
    private func tick(deltaTime: TimeInterval) {
        // If the route isn't built yet (first layout pass had a degenerate
        // size), don't spawn and don't bank time — otherwise a burst of
        // zombies appears all at once when the path finally exists.
        if path.isEmpty {
            zombieManager.resetSpawnTimer()
            setUpPath()
        } else {
            zombieManager.updateSpawning(deltaTime: deltaTime)
        }

        zombieManager.move(deltaTime: deltaTime)
        towerManager.updateFire(deltaTime: deltaTime)   // MH2D-12 TEMP test shooters
        projectileSystem.update(deltaTime: deltaTime, bounds: size) // MH2D-46 collision checks

        tickCount += 1
        updateDebugStats()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        refreshTowerPanel()
    }

    // MARK: - Debug overlay (hitboxes) and stress test (MH2D-12)

    private var stressMode = false
    private var hitboxToggleLabel: SKLabelNode?
    private var stressToggleLabel: SKLabelNode?

    private func setUpHitboxDebugControls() {
        func makeToggle() -> SKLabelNode {
            let label = SKLabelNode(fontNamed: "Menlo")
            label.fontSize = 12
            label.fontColor = .yellow
            label.horizontalAlignmentMode = .left
            label.zPosition = Layer.hud.rawValue
            addChild(label)
            return label
        }
        hitboxToggleLabel = makeToggle()
        stressToggleLabel = makeToggle()
        updateDebugToggleLabels()
    }

    private func layoutDebugControls() {
        let left = lastSafeArea.left + 16
        hitboxToggleLabel?.position = CGPoint(x: left, y: size.height - lastSafeArea.top - 46)
        stressToggleLabel?.position = CGPoint(x: left, y: size.height - lastSafeArea.top - 66)
    }

    private func updateDebugToggleLabels() {
        hitboxToggleLabel?.text = "hitboxes: \(DebugOverlay.showHitboxes ? "ON " : "OFF") (tap)"
        stressToggleLabel?.text = "stress test: \(stressMode ? "ON " : "OFF") (tap)"
    }

    private func toggleHitboxes() {
        DebugOverlay.showHitboxes.toggle()
        for name in DebugOverlay.circleNames {
            worldNode.enumerateChildNodes(withName: "//" + name) { node, _ in
                node.isHidden = !DebugOverlay.showHitboxes
            }
        }
        updateDebugToggleLabels()
    }

    /// Stress test: zombies spawn every 0.4 s so 20+ are on screen at once.
    private func toggleStress() {
        stressMode.toggle()
        zombieManager.spawnInterval = stressMode ? 0.4 : zombieManager.normalSpawnInterval
        updateDebugToggleLabels()
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
        debugLabel?.text = "ticks \(tickCount) | zombies \(zombieManager.zombies.count) | shots \(projectileSystem.activeCount) | hits \(projectileSystem.hitCount) | misses \(projectileSystem.missCount)"
    }
}
