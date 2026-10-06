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
        money: 1000, // TEMP test value so you can place many towers; set back to ~150 later
        unlockedTowers: TowerType.allCases
    )
    private let towerPanel = SKSpriteNode(color: UIColor(white: 0.10, alpha: 1), size: .zero)
    private var towerCards: [(TowerType, SKShapeNode)] = []
    private var cancelButton: SKSpriteNode?
    private var sellButton: SKSpriteNode?
    /// Index into placedTowers of the tower the player tapped (for selling).
    private var selectedPlacedIndex: Int?
    private let sellRefundRate: Double = 0.7
    private let selectionLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let placementPreview = SKNode()
    private var lastSafeArea: UIEdgeInsets = .zero

    // MH2D-8: tower placement state.
    private var previewOutline: SKShapeNode?
    private var placedTowers: [(type: TowerType, node: SKNode)] = []
    /// True while a tower card is being dragged toward the map.
    private var isDraggingTower = false
    /// True when the current touch began on the Sell button.
    private var touchStartedOnSell = false
    /// Offset of the placement preview from the finger/cursor. Zero = the
    /// tower is centered exactly on the touch point (raise y to float it
    /// above a finger on a real phone).
    private let dragOffset = CGPoint(x: 0, y: 0)
    private let towerRadius: CGFloat = 22
    private let pathHalfWidth: CGFloat = 16 // path is drawn 32 wide
    private let towerGap: CGFloat = 6        // min empty space between towers

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

        let heading = makeLabel("Towers · $\(towerSelection.money)", size: 16)
        heading.horizontalAlignmentMode = .left
        heading.position = CGPoint(x: left, y: panelHeight - 22)
        towerPanel.addChild(heading)

        // (No Cancel button: placement is drag-and-drop, so releasing over
        // the panel cancels.)

        // Sell button: only while a placed tower is selected (never at the
        // same time as placement mode).
        if let index = selectedPlacedIndex, placedTowers.indices.contains(index) {
            let refund = sellValue(of: placedTowers[index].type)
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
        if let tower = towerSelection.selectedTower {
            selectionLabel.text = "Drag to the map and release to place \(tower.displayName)"
        } else if let index = selectedPlacedIndex, placedTowers.indices.contains(index) {
            selectionLabel.text = "\(placedTowers[index].type.displayName) selected · tap Sell to remove it"
        } else {
            selectionLabel.text = "Drag a tower from the panel onto the map"
        }
        debugLabel?.position = CGPoint(x: left, y: size.height - lastSafeArea.top - 24)
        layoutDebugControls()
        updatePlacementPreview()
        setUpPath()
    
    }
    //this will spawn zombies - Adam
    private func spawnZombie() {
        guard let startPoint = pathWaypoints.first else { return }

        let zombie = SKShapeNode(circleOfRadius: GameScene.zombieRadius)
        zombie.name = "zombie"
        zombie.fillColor = .systemGreen
        zombie.strokeColor = .black
        zombie.lineWidth = 2
        zombie.position = startPoint
        zombie.zPosition = Layer.zombies.rawValue
        // MH2D-12: outline of the hurtbox (only visible when the overlay is on)
        zombie.addChild(makeDebugCircle(radius: GameScene.zombieRadius, color: .yellow, name: "hurtboxDebug"))

        worldNode.addChild(zombie)
        zombies.append(ZombieState(node: zombie))
    } //Ends spawnZombie()
    
    private func moveZombie(deltaTime: TimeInterval) {
        // Work backward so removing a zombie doesn't shift
        // the indexes of zombies we still need to update.
        for index in zombies.indices.reversed() {
            let zombie = zombies[index].node
            // Ice tower slow: zombies crawl at iceSlowFactor of normal speed.
            var speedMultiplier: CGFloat = 1
            if zombies[index].slowTimer > 0 {
                zombies[index].slowTimer -= deltaTime
                speedMultiplier = GameScene.iceSlowFactor
                zombie.fillColor = .systemTeal
            } else {
                zombie.fillColor = .systemGreen
            }
            var remainingMovement = zombieSpeed * speedMultiplier * CGFloat(deltaTime)

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
        let outline = SKShapeNode(circleOfRadius: towerRadius)
        outline.strokeColor = .systemYellow
        outline.lineWidth = 2
        // Range radius of the tower being dragged (see MH2D-12 testSpec).
        placementPreview.addChild(makeRangeRing(radius: testSpec(for: tower).range))
        placementPreview.addChild(outline)
        previewOutline = outline
        placementPreview.addChild(towerIcon(tower, enabled: true))
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
                    deselectPlacedTower()          // picking a card leaves "tower selected" mode
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
        selectPlacedTower(at: point)
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

    // MARK: - MH2D-8: Tower placement

    /// Map area above the tower panel and inside the safe area.
    private func isInPlayfield(_ point: CGPoint) -> Bool {
        point.y > towerPanel.size.height + 24
            && point.y < size.height - lastSafeArea.top - 24
            && point.x > lastSafeArea.left + 24
            && point.x < size.width - lastSafeArea.right - 24
    }

    /// Shortest distance from a point to the zombie route (all segments).
    private func distanceToPath(from point: CGPoint) -> CGFloat {
        guard pathWaypoints.count >= 2 else { return .greatestFiniteMagnitude }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 1..<pathWaypoints.count {
            let a = pathWaypoints[i - 1]
            let b = pathWaypoints[i]
            let abx = b.x - a.x
            let aby = b.y - a.y
            let lengthSquared = abx * abx + aby * aby
            var t: CGFloat = 0
            if lengthSquared > 0 {
                t = max(0, min(1, ((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSquared))
            }
            let closest = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
            best = min(best, hypot(point.x - closest.x, point.y - closest.y))
        }
        return best
    }

    /// A spot is valid if it is on the map, clear of the path edge, and
    /// doesn't overlap an already placed tower.
    private func isValidPlacement(at point: CGPoint) -> Bool {
        guard isInPlayfield(point) else { return false }
        if distanceToPath(from: point) < pathHalfWidth + towerRadius { return false }
        for placed in placedTowers {
            let d = hypot(point.x - placed.node.position.x, point.y - placed.node.position.y)
            if d < towerRadius * 2 + towerGap { return false }
        }
        return true
    }

    /// Green outline = can place here, red = can't.
    private func updatePreviewValidity() {
        previewOutline?.strokeColor = isValidPlacement(at: placementPreview.position)
            ? .systemGreen : .systemRed
    }

    // MARK: - Sell tower

    private func sellValue(of type: TowerType) -> Int {
        Int((Double(type.cost) * sellRefundRate).rounded())
    }

    private func deselectPlacedTower() {
        if let index = selectedPlacedIndex, placedTowers.indices.contains(index) {
            placedTowers[index].node.childNode(withName: "selectionRing")?.removeFromParent()
            placedTowers[index].node.childNode(withName: "rangeRing")?.removeFromParent()
        }
        selectedPlacedIndex = nil
    }

    /// Select the placed tower under the touch (if any); otherwise deselect.
    private func selectPlacedTower(at point: CGPoint) {
        let hit = placedTowers.firstIndex {
            hypot(point.x - $0.node.position.x, point.y - $0.node.position.y) <= towerRadius + 10
        }
        guard hit != selectedPlacedIndex else { return }
        deselectPlacedTower()
        if let hit {
            selectedPlacedIndex = hit
            let ring = SKShapeNode(circleOfRadius: towerRadius + 5)
            ring.name = "selectionRing"
            ring.strokeColor = .systemYellow
            ring.lineWidth = 3
            placedTowers[hit].node.addChild(ring)
            // Show how far this tower can shoot while it's selected.
            placedTowers[hit].node.addChild(makeRangeRing(radius: testSpec(for: placedTowers[hit].type).range))
        }
        refreshTowerPanel()
    }

    /// Remove the selected tower, refund part of its cost, free its spot.
    private func sellSelectedTower() {
        guard let index = selectedPlacedIndex, placedTowers.indices.contains(index) else { return }
        let sold = placedTowers.remove(at: index)
        fireTimers.removeValue(forKey: ObjectIdentifier(sold.node))
        sold.node.removeFromParent()
        selectedPlacedIndex = nil
        towerSelection.updateMoney(towerSelection.money + sellValue(of: sold.type))
        refreshTowerPanel()
    }

    private func placeTower(at point: CGPoint) {
        guard let type = towerSelection.selectedTower,
              towerSelection.canSelect(type),
              isValidPlacement(at: point) else { return } // rejected: nothing placed, no money spent

        let node = SKNode()
        node.name = "tower"
        node.position = point
        node.zPosition = Layer.towers.rawValue

        let color = towerColor(type)
        let base = SKShapeNode(circleOfRadius: towerRadius)
        base.fillColor = color.withAlphaComponent(0.25)
        base.strokeColor = color
        base.lineWidth = 2
        node.addChild(base)
        node.addChild(towerIcon(type, enabled: true))
        // MH2D-12: shows the tower's range when the hitbox overlay is on.
        node.addChild(makeDebugCircle(radius: testSpec(for: type).range,
                                      color: UIColor.white.withAlphaComponent(0.5),
                                      name: "rangeDebug"))

        worldNode.addChild(node)
        placedTowers.append((type: type, node: node))

        // Pay, leave placement mode, and refresh the panel (money, card states).
        towerSelection.updateMoney(towerSelection.money - type.cost)
        towerSelection.cancel()
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

    /// This is where MH2D-7 (zombie movement), MH2D-9 (tower targeting),
    /// wave timers, etc. will eventually plug in. For Sprint 1 it just
    /// proves the loop runs at a stable, fixed rate.
    private func tick(deltaTime: TimeInterval) {
        // FIX #3: if the route isn't built yet (first layout pass had a
        // degenerate size), don't spawn and don't bank time — otherwise a
        // burst of zombies appears all at once when the path finally exists.
        if pathWaypoints.isEmpty {
            spawnTimer = 0
            setUpPath()
        } else {
            spawnTimer += deltaTime

            while spawnTimer >= spawnInterval {
                spawnTimer -= spawnInterval
                spawnZombie()
            }
        }

        moveZombie(deltaTime: deltaTime)
        updateTowerFire(deltaTime: deltaTime)   // MH2D-12 TEMP test shooters
        updateProjectiles(deltaTime: deltaTime) // MH2D-46 collision checks

        tickCount += 1
        updateDebugStats()
    }
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        refreshTowerPanel()
    }
    // MARK: - MH2D-12: Hit/hurt boxes
    //
    // Bloons-style: every collision shape is a circle, checked by hand inside
    // the fixed 30 Hz tick (not SpriteKit physics), so combat behaves the same
    // on every device. Projectiles use a *swept* test (their whole path this
    // tick vs the zombie's circle), so a fast shot can never skip over a
    // zombie between two ticks.

    /// MH2D-45: a zombie's "can be hit" circle, centered on its node.
    struct Hurtbox { var radius: CGFloat }
    /// MH2D-45: a projectile's "deals a hit" circle, centered on its node.
    struct Hitbox { var radius: CGFloat }

    /// Look and numbers for one tower type's projectile. TEMP values: when
    /// MH2D-9 (real tower stats/art) lands, replace `testSpec(for:)` with each
    /// tower's real numbers and `makeProjectileNode(_:)` with its real sprite.
    struct ProjectileSpec {
        var radius: CGFloat          // hitbox radius (also the drawn size)
        var speed: CGFloat           // points per second
        var color: UIColor
        var range: CGFloat           // how far the tower can shoot
        var fireInterval: TimeInterval
        var lifetime: TimeInterval   // seconds before a missed shot disappears
    }

    private func testSpec(for tower: TowerType) -> ProjectileSpec {
        switch tower {
        case .soldier:
            return ProjectileSpec(radius: 4, speed: 380, color: .systemYellow, range: 80, fireInterval: 0.6, lifetime: 1.2)
        case .sniper:
            return ProjectileSpec(radius: 3, speed: 700, color: .white, range: 168, fireInterval: 1.6, lifetime: 1.2)
        case .ice:
            return ProjectileSpec(radius: 7, speed: 240, color: .systemCyan, range: 68, fireInterval: 1.0, lifetime: 1.5)
        }
    }

    /// Swap this to change what a projectile looks like (sprite, trail, ...).
    private func makeProjectileNode(_ spec: ProjectileSpec) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: spec.radius)
        node.fillColor = spec.color
        node.strokeColor = .clear
        node.zPosition = Layer.projectiles.rawValue
        return node
    }

    private struct ProjectileState {
        let node: SKShapeNode
        var velocity: CGVector
        let hitbox: Hitbox
        var age: TimeInterval = 0
        let lifetime: TimeInterval
    }

    private var projectiles: [ProjectileState] = []
    private var fireTimers: [ObjectIdentifier: TimeInterval] = [:]
    private var hitCount = 0
    private var missCount = 0
    private var showHitboxes = false
    private var stressMode = false
    private var hitboxToggleLabel: SKLabelNode?
    private var stressToggleLabel: SKLabelNode?

    /// TEMP test shooter: each placed tower fires at the nearest zombie in
    /// range. MH2D-9 (Adam) replaces this with real targeting.
    private func updateTowerFire(deltaTime: TimeInterval) {
        for placed in placedTowers {
            let spec = testSpec(for: placed.type)
            let key = ObjectIdentifier(placed.node)
            let timer = (fireTimers[key] ?? 0) + deltaTime
            guard timer >= spec.fireInterval else {
                fireTimers[key] = timer
                continue
            }

            // Ice tower: area slow pulse on everything in range. No damage.
            if placed.type == .ice {
                var slowedAny = false
                for i in zombies.indices {
                    let d = hypot(zombies[i].node.position.x - placed.node.position.x,
                                  zombies[i].node.position.y - placed.node.position.y)
                    if d <= spec.range {
                        zombies[i].slowTimer = GameScene.iceSlowDuration
                        slowedAny = true
                    }
                }
                guard slowedAny else {
                    fireTimers[key] = spec.fireInterval // ready; waits for a target
                    continue
                }
                fireTimers[key] = 0
                showFrostPulse(at: placed.node.position, radius: spec.range, color: spec.color)
                continue
            }

            var nearest: (index: Int, distance: CGFloat)?
            for (i, zombie) in zombies.enumerated() {
                let d = hypot(zombie.node.position.x - placed.node.position.x,
                              zombie.node.position.y - placed.node.position.y)
                if d <= spec.range, d < (nearest?.distance ?? .greatestFiniteMagnitude) {
                    nearest = (i, d)
                }
            }
            guard let target = nearest else {
                fireTimers[key] = spec.fireInterval // ready; waits for a target
                continue
            }
            fireTimers[key] = 0
            fireProjectile(from: placed.node.position, at: zombies[target.index], spec: spec)
        }
    }

    /// Expanding ring that shows an ice tower's slow pulse.
    private func showFrostPulse(at position: CGPoint, radius: CGFloat, color: UIColor) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = position
        ring.fillColor = color.withAlphaComponent(0.15)
        ring.strokeColor = color
        ring.lineWidth = 2
        ring.zPosition = Layer.projectiles.rawValue
        ring.setScale(0.2)
        worldNode.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 1, duration: 0.35), .fadeOut(withDuration: 0.35)]),
            .removeFromParent()
        ]))
    }

    private func fireProjectile(from origin: CGPoint, at zombie: ZombieState, spec: ProjectileSpec) {
        // Aim where the zombie will be when the shot arrives (first-order lead).
        let pos = zombie.node.position
        var aim = pos
        if zombie.nextWaypointIndex < pathWaypoints.count {
            let next = pathWaypoints[zombie.nextWaypointIndex]
            let dx = next.x - pos.x
            let dy = next.y - pos.y
            let length = hypot(dx, dy)
            if length > 0 {
                let flightTime = hypot(pos.x - origin.x, pos.y - origin.y) / spec.speed
                let reach = min(length, zombieSpeed * flightTime)
                aim = CGPoint(x: pos.x + dx / length * reach, y: pos.y + dy / length * reach)
            }
        }
        let ax = aim.x - origin.x
        let ay = aim.y - origin.y
        let aimLength = hypot(ax, ay)
        guard aimLength > 0 else { return }

        let node = makeProjectileNode(spec)
        node.position = origin
        node.addChild(makeDebugCircle(radius: spec.radius, color: .red, name: "hitboxDebug"))
        worldNode.addChild(node)
        projectiles.append(ProjectileState(
            node: node,
            velocity: CGVector(dx: ax / aimLength * spec.speed, dy: ay / aimLength * spec.speed),
            hitbox: Hitbox(radius: spec.radius),
            lifetime: spec.lifetime
        ))
    }

    /// MH2D-46: move every projectile and check it against every hurtbox.
    private func updateProjectiles(deltaTime: TimeInterval) {
        for index in projectiles.indices.reversed() {
            var shot = projectiles[index]
            let from = shot.node.position
            let to = CGPoint(x: from.x + shot.velocity.dx * CGFloat(deltaTime),
                             y: from.y + shot.velocity.dy * CGFloat(deltaTime))
            shot.age += deltaTime

            // Swept check against all zombies; keep the earliest contact.
            var hitIndex: Int?
            var earliest = CGFloat.greatestFiniteMagnitude
            for (zi, zombie) in zombies.enumerated() {
                let reach = shot.hitbox.radius + zombie.hurtbox.radius
                if let t = sweptCircleHit(from: from, to: to, center: zombie.node.position, radius: reach),
                   t < earliest {
                    earliest = t
                    hitIndex = zi
                }
            }

            if let zi = hitIndex {
                registerHit(onZombieAt: zi)
                shot.node.removeFromParent()
                projectiles.remove(at: index)
                continue
            }

            shot.node.position = to
            let outside = to.x < 0 || to.y < 0 || to.x > size.width || to.y > size.height
            if shot.age >= shot.lifetime || outside {
                shot.node.removeFromParent()
                projectiles.remove(at: index)
                missCount += 1
            } else {
                projectiles[index] = shot
            }
        }
    }

    /// Does the path a→b come within `radius` of `center`? Returns how far
    /// along the path (0...1) the closest approach is, or nil for a miss.
    private func sweptCircleHit(from a: CGPoint, to b: CGPoint, center c: CGPoint, radius r: CGFloat) -> CGFloat? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        var t: CGFloat = 0
        if lengthSquared > 0 {
            t = max(0, min(1, ((c.x - a.x) * dx + (c.y - a.y) * dy) / lengthSquared))
        }
        let closest = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
        return hypot(c.x - closest.x, c.y - closest.y) <= r ? t : nil
    }

    /// For now a hit just counts and flashes the zombie red. Damage and death
    /// belong to MH2D-51 (apply damage on hit).
    private func registerHit(onZombieAt index: Int) {
        hitCount += 1
        // TEMP: one hit removes the zombie (quick red pop, then gone).
        // MH2D-51 replaces this with real damage and health.
        let node = zombies[index].node
        zombies.remove(at: index)
        node.removeAllActions()
        node.fillColor = .systemRed
        node.run(.sequence([
            .group([.fadeOut(withDuration: 0.12), .scale(to: 1.4, duration: 0.12)]),
            .removeFromParent()
        ]))
    }

    // MARK: Debug overlay (hitboxes) and stress test

    private func makeDebugCircle(radius: CGFloat, color: UIColor, name: String) -> SKShapeNode {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.name = name
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 1.5
        ring.zPosition = 5
        ring.isHidden = !showHitboxes
        return ring
    }

    /// Soft filled circle showing a tower's shooting range. Shown while a
    /// tower is being dragged and while a placed tower is selected.
    private func makeRangeRing(radius: CGFloat) -> SKShapeNode {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.name = "rangeRing"
        ring.fillColor = UIColor.white.withAlphaComponent(0.08)
        ring.strokeColor = UIColor.white.withAlphaComponent(0.55)
        ring.lineWidth = 1.5
        ring.zPosition = -1 // behind the tower icon and its outline
        return ring
    }

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
        hitboxToggleLabel?.text = "hitboxes: \(showHitboxes ? "ON " : "OFF") (tap)"
        stressToggleLabel?.text = "stress test: \(stressMode ? "ON " : "OFF") (tap)"
    }

    private func toggleHitboxes() {
        showHitboxes.toggle()
        for name in ["hurtboxDebug", "hitboxDebug", "rangeDebug"] {
            worldNode.enumerateChildNodes(withName: "//" + name) { node, _ in
                node.isHidden = !self.showHitboxes
            }
        }
        updateDebugToggleLabels()
    }

    /// Stress test: zombies spawn every 0.4 s so 20+ are on screen at once.
    private func toggleStress() {
        stressMode.toggle()
        spawnInterval = stressMode ? 0.4 : normalSpawnInterval
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
        debugLabel?.text = "ticks \(tickCount) | zombies \(zombies.count) | shots \(projectiles.count) | hits \(hitCount) | misses \(missCount)"
    }
    
    // Ordered points that zombies will follow - Adam
    private var pathWaypoints: [CGPoint] = []
    
    /// Drawn radius of a zombie; its hurtbox uses the same number so the
    /// box always lines up with what you see.
    private static let zombieRadius: CGFloat = 12

    private struct ZombieState {
        let node: SKShapeNode
        var nextWaypointIndex: Int = 1
        var hurtbox = Hurtbox(radius: GameScene.zombieRadius) // MH2D-45
        var slowTimer: TimeInterval = 0 // > 0 while slowed by an ice tower
    }

    private var zombies: [ZombieState] = []
    private let zombieSpeed: CGFloat = 60
    private static let iceSlowFactor: CGFloat = 0.45   // 45% speed while slowed
    private static let iceSlowDuration: TimeInterval = 2.0

    private var spawnTimer: TimeInterval = 0
    private let normalSpawnInterval: TimeInterval = 1.5
    private var spawnInterval: TimeInterval = 1.5 // stress test shortens this
    
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

        let newWaypoints = [
            CGPoint(x: left, y: lowerY),       // Start
            CGPoint(x: middleX, y: lowerY),    // Walk right
            CGPoint(x: middleX, y: upperY),    // Turn upward
            CGPoint(x: right, y: upperY)      // Walk right to the end
        ]

        // FIX #2: refreshTowerPanel() calls this on every tap/money change.
        // If the route hasn't moved, there is nothing to rebuild.
        if newWaypoints == pathWaypoints,
           worldNode.childNode(withName: "zombiePath") != nil {
            return
        }

        // FIX #1: zombies store an index into pathWaypoints, so if the
        // route moves they would snap to the new coordinates. Remember how
        // far along its current segment each zombie is, then re-apply that
        // fraction to the new route.
        let oldWaypoints = pathWaypoints
        let progress: [CGFloat] = zombies.map { zombie in
            let next = zombie.nextWaypointIndex
            guard next >= 1, next < oldWaypoints.count else { return 0 }
            let from = oldWaypoints[next - 1]
            let to = oldWaypoints[next]
            let length = hypot(to.x - from.x, to.y - from.y)
            guard length > 0 else { return 0 }
            let travelled = hypot(zombie.node.position.x - from.x,
                                  zombie.node.position.y - from.y)
            return min(1, travelled / length)
        }

        pathWaypoints = newWaypoints

        for (index, t) in progress.enumerated() {
            let next = zombies[index].nextWaypointIndex
            guard next >= 1, next < pathWaypoints.count else { continue }
            let from = pathWaypoints[next - 1]
            let to = pathWaypoints[next]
            zombies[index].node.position = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t
            )
        }

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
        pathNode.lineJoin = .round // smooth corners instead of clipped ones
        pathNode.lineCap = .round
        pathNode.zPosition = Layer.path.rawValue

        worldNode.addChild(pathNode)
    }
}
