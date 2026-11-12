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

    /// Which map this game is played on (set before the scene is shown).
    var map: MapDefinition = .meadowRun
    private lazy var path = GamePath(world: worldNode, map: map)
    private lazy var zombieManager = ZombieManager(world: worldNode, path: path)
    private lazy var projectileSystem = ProjectileSystem(world: worldNode, zombies: zombieManager, path: path)
    private lazy var towerManager = TowerManager(world: worldNode, path: path,
                                                 zombies: zombieManager, projectiles: projectileSystem)

    /// The player's money (Economy/PlayerWallet.swift). `towerSelection` only
    /// mirrors the total so the panel can show/grey out towers.
    private let wallet = PlayerWallet()

    // Sample settings: adjust prices in TowerSelection.swift.
    private(set) var towerSelection = TowerSelectionState(
        money: PlayerWallet.startingMoney, // the wallet owns the real total; this mirrors it for the panel
        unlockedTowers: TowerType.allCases
    )

    // MARK: Tower panel / placement UI state
    private let towerPanel = SKSpriteNode(color: UIColor(white: 0.10, alpha: 1), size: .zero)
    private var towerCards: [(TowerType, SKShapeNode)] = []
    private var cancelButton: SKSpriteNode?
    private var sellButton: SKSpriteNode?
    /// Money changed since the panel was last drawn (redrawn at most every `panelRefreshInterval`).
    private var panelDirty = false
    /// Labels that count down "Need $X" so they can be updated in place without a rebuild.
    private var needLabels: [(tower: TowerType, label: SKLabelNode)] = []
    private var upgradeNeedLabels: [(cost: Int, label: SKLabelNode)] = []
    /// Which cards / the Upgrade button were affordable when the panel was last drawn.
    private var drawnAffordability: [Bool] = []
    private func currentAffordability() -> [Bool] {
        var result = towerSelection.unlockedTowers.map { towerSelection.canSelect($0) }
        for path in 0..<TowerUpgrade.pathCount { result.append(towerManager.upgradeCost(path: path).map { wallet.canAfford($0) } ?? false) }
        return result
    }

    private var lastPanelRefreshTime: TimeInterval = 0
    private let panelRefreshInterval: TimeInterval = 0.25
    private var priorityButton: SKSpriteNode?
    private var upgradeButtons: [(path: Int, node: SKSpriteNode)] = []   // only while a placed tower is selected
    private var pendingUpgradePath: Int?
    private let selectionLabel = OutlinedLabel(fontNamed: "AvenirNext-Medium")
    private let waveLabel = OutlinedLabel(fontNamed: "AvenirNext-DemiBold")
    private let baseHealthLabel = OutlinedLabel(fontNamed: "AvenirNext-DemiBold")
    private let moneyLabel = OutlinedLabel(fontNamed: "AvenirNext-DemiBold") // MH2D-69 HUD currency
    private let baseHealth = BaseHealth() // MH2D-56 / MH2D-126
    private var isGameOver = false          // MH2D-57
    private var gameOverOverlay: GameOverOverlay?   // MH2D-81
    private let pauseButton = SKShapeNode(rectOf: CGSize(width: 40, height: 32), cornerRadius: 8)
    /// Fast-forward button: toggles 1x <-> 1.5x (like Bloons TD).
    private let nextWaveButton = SKShapeNode(rectOf: CGSize(width: 150, height: 32), cornerRadius: 8)
    private let nextWaveLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let speedButton = SKShapeNode(rectOf: CGSize(width: 52, height: 32), cornerRadius: 8)
    private let speedLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var gameSpeed: Double = 1
    private var pauseOverlay: PauseOverlay?
    private var isPauseMenuUp: Bool { pauseOverlay != nil }
    private var isWinScreenUp = false               // all waves cleared; waiting for Continue / Main Menu
    private var victoryOverlay: VictoryOverlay?
    private var victoryShownAt: TimeInterval?
    private var gameOverShownAt: TimeInterval?      // MH2D-82: ignore taps for a moment
    private static let gameOverTapDelay: TimeInterval = 0.6
    /// MH2D-82: set by GameViewController. Retry builds a fresh scene; the
    /// Main Menu button only shows once `onMainMenuRequested` is set (MH2D-22).
    var onRetryRequested: (() -> Void)?
    var onMainMenuRequested: (() -> Void)?
    private let runStats = RunStats()       // MH2D-81
    private let placementPreview = SKNode()
    private var lastSafeArea: UIEdgeInsets = .zero
    private var previewOutline: SKShapeNode?
    /// True while a tower card is being dragged toward the map.
    private var isDraggingTower = false
    /// True when the current touch began on the Sell button.
    private var touchStartedOnSell = false
    private var touchStartedOnUpgrade = false

    // Scrolling tower panel: drag up/down to scroll, pull a card left to place it.
    private var panelContent: SKNode?
    private var panelThumb: SKShapeNode?
    private var panelScroll: CGFloat = 0
    private var panelMaxScroll: CGFloat = 0
    private var panelViewportTop: CGFloat = 0
    private var panelViewportHeight: CGFloat = 0
    private var panelThumbHeight: CGFloat = 0
    private var pendingCard: TowerType?
    private var panelTouchStart: CGPoint?
    private var panelScrollStart: CGFloat = 0
    private var isScrollingPanel = false
    /// Offset of the placement preview from the finger/cursor. Zero = the
    /// tower is centered exactly on the touch point (raise y to float it
    /// above a finger on a real phone).
    private let dragOffset = CGPoint(x: 0, y: 0)

    override func didMove(to view: SKView) {
        DamageEffects.reset()
        super.didMove(to: view)

        // Scaffolding: background, scaling, coordinate origin.
        scaleMode = .resizeFill
        backgroundColor = map.theme.ground
        anchorPoint = CGPoint(x: 0, y: 0) // origin at bottom-left; simplest for tile/grid math

        guard worldNode.parent == nil else {
            refreshTowerPanel()
            return
        }
        addChild(worldNode)
        waveLabel.fontSize = 20
        waveLabel.fontColor = .white
        waveLabel.horizontalAlignmentMode = .left
        waveLabel.verticalAlignmentMode = .top
        waveLabel.zPosition = Layer.hud.rawValue
        waveLabel.text = "Wave \(zombieManager.currentWave)/\(zombieManager.totalWaves)"
        addChild(waveLabel)
        
        baseHealthLabel.fontSize = 20
        baseHealthLabel.fontColor = .systemRed
        baseHealthLabel.horizontalAlignmentMode = .right
        baseHealthLabel.verticalAlignmentMode = .top
        baseHealthLabel.zPosition = Layer.hud.rawValue
        baseHealthLabel.text = "♥ \(baseHealth.current)"
        addChild(baseHealthLabel)

        // MH2D-69: currency in the HUD (below wave and base health).
        moneyLabel.fontSize = 20
        moneyLabel.fontColor = .systemYellow
        moneyLabel.horizontalAlignmentMode = .left
        moneyLabel.verticalAlignmentMode = .top
        moneyLabel.zPosition = Layer.hud.rawValue
        moneyLabel.text = "$\(wallet.money)"
        addChild(moneyLabel)
        
        
        setUpTowerPanel()

        // Any wallet change updates the tower menu and redraws the panel.
        wallet.onChange = { [weak self] money in
            guard let self else { return }
            self.towerSelection.updateMoney(money)
            self.moneyLabel.text = "$\(money)" // MH2D-70: HUD follows the wallet
            // Rebuilding the whole panel (every tower icon) is expensive, and
            // kills pay out many times a second. So only the "Need $X" numbers
            // change in place; the panel is redrawn (at most a few times per
            // second, in update()) only when a card or the Upgrade button flips
            // between affordable and not.
            for entry in self.needLabels {
                entry.label.text = "Need $\(max(0, entry.tower.cost - money))"
            }
            for entry in self.upgradeNeedLabels {
                entry.label.text = "Need $\(max(0, entry.cost - money))"
            }
            if self.currentAffordability() != self.drawnAffordability {
                self.panelDirty = true
            }
        }
        // MH2D-53: kills pay the player.
        zombieManager.onZombieKilled = { [weak self] reward in
            self?.wallet.add(reward)
            SoundManager.shared.play(.kill)
        }
        
        // MH2D-56: a zombie that reaches the end costs the base 1 health.
        zombieManager.onZombieReachedBase = { [weak self] in
            self?.baseHealth.damage(1)
            SoundManager.shared.play(.baseHit)
        }
        baseHealth.onChange = { [weak self] health in
            self?.baseHealthLabel.text = "♥ \(health)"
        }
        // MH2D-57: base health reaching 0 ends the game.
        baseHealth.onDepleted = { [weak self] in
            self?.triggerGameOver()
        }

        zombieManager.onAllWavesCompleted = { [weak self] in
            self?.showVictory()
        }
        zombieManager.onWaveCompleted = { [weak self] _ in
            self?.runStats.recordWaveSurvived()
            self?.wallet.add(50)
            SoundManager.shared.play(.wave)
        }

        // The green debug stats bar is off. Call setUpDebugStats(in: view) here to bring it back.
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
        // The bottom-left hint text is no longer shown (the label is kept but not added to the scene).

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
        panelDirty = false
        towerPanel.removeAllChildren()
        towerCards.removeAll()
        needLabels.removeAll()
        upgradeNeedLabels.removeAll()
        cancelButton = nil
        sellButton = nil
        upgradeButtons.removeAll()
        priorityButton = nil
        lastSafeArea = view?.safeAreaInsets ?? .zero
        
        // HUD: wave and money in the top-left corner, base health in the top-right corner of the map.
        let hudLeft = lastSafeArea.left + 12
        let hudTop = size.height - lastSafeArea.top

        waveLabel.position = CGPoint(x: hudLeft, y: hudTop - 12)
        moneyLabel.position = CGPoint(x: hudLeft, y: hudTop - 40)

        let left = lastSafeArea.left + 16

        // The tower panel is a column down the right edge of the screen.
        // Everything below is in the panel's own coordinates (0,0 = its
        // bottom-left corner); the map gets whatever space is left over.
        let towers = towerSelection.unlockedTowers
        let columns = 1
        let panelInnerWidth: CGFloat = 112   // narrow, so the map gets the room
        let panelWidth = panelInnerWidth + lastSafeArea.right
        let panelLeftEdge = size.width - panelWidth
        let gap: CGFloat = 8
        let headerHeight: CGFloat = 48
        let cardHeight: CGFloat = 64
        let sellWidth = panelInnerWidth - 16
        let cardWidth = sellWidth
        let panelTop = size.height - lastSafeArea.top
        towerPanel.position = CGPoint(x: panelLeftEdge, y: 0)
        towerPanel.size = CGSize(width: panelWidth, height: size.height)

        baseHealthLabel.position = CGPoint(x: panelLeftEdge - 12, y: hudTop - 12)
        pauseButton.position = CGPoint(x: panelLeftEdge - 110, y: hudTop - 24)
        if pauseButton.parent == nil {
            pauseButton.fillColor = SKColor(white: 0, alpha: 0.45)
            pauseButton.strokeColor = .white
            pauseButton.lineWidth = 2
            pauseButton.zPosition = Layer.hud.rawValue
            for x: CGFloat in [-5, 5] {
                let bar = SKShapeNode(rectOf: CGSize(width: 5, height: 14), cornerRadius: 1)
                bar.fillColor = .white
                bar.strokeColor = .clear
                bar.position = CGPoint(x: x, y: 0)
                pauseButton.addChild(bar)
            }
            addChild(pauseButton)
        }
        nextWaveButton.position = CGPoint(x: panelLeftEdge - 168 - 115, y: hudTop - 24)
        if nextWaveButton.parent == nil {
            nextWaveButton.fillColor = SKColor.systemGreen.withAlphaComponent(0.9)
            nextWaveButton.strokeColor = .white
            nextWaveButton.lineWidth = 2
            nextWaveButton.zPosition = Layer.hud.rawValue
            nextWaveLabel.fontSize = 15
            nextWaveLabel.fontColor = .white
            nextWaveLabel.verticalAlignmentMode = .center
            nextWaveLabel.horizontalAlignmentMode = .center
            nextWaveButton.addChild(nextWaveLabel)
            nextWaveButton.run(.repeatForever(.sequence([.scale(to: 1.06, duration: 0.6), .scale(to: 1.0, duration: 0.6)])))
            addChild(nextWaveButton)
        }
        speedButton.position = CGPoint(x: panelLeftEdge - 168, y: hudTop - 24)
        if speedButton.parent == nil {
            speedButton.strokeColor = .white
            speedButton.lineWidth = 2
            speedButton.zPosition = Layer.hud.rawValue
            speedLabel.fontSize = 16
            speedLabel.fontColor = .white
            speedLabel.verticalAlignmentMode = .center
            speedLabel.horizontalAlignmentMode = .center
            speedButton.addChild(speedLabel)
            addChild(speedButton)
            updateSpeedButton()
        }

        // Tell the tower system where towers may be placed (left of the panel).
        towerManager.playfield = TowerManager.Playfield(
            minX: lastSafeArea.left,   // the notch side keeps its safe area
            maxX: panelLeftEdge,
            minY: 0,
            maxY: size.height
        )

        let heading = makeLabel("Towers", size: 16)
        heading.horizontalAlignmentMode = .left
        heading.position = CGPoint(x: 8, y: panelTop - 24)
        towerPanel.addChild(heading)

        // (No Cancel button: placement is drag-and-drop, so releasing over
        // the panel cancels.)

        // Sell button: only while a placed tower is selected (never at the
        // same time as placement mode).
        if let selectedTower = towerManager.selected {
            let refund = TowerManager.sellValue(of: selectedTower)
            let sell = SKSpriteNode(color: .systemRed, size: CGSize(width: sellWidth, height: 36))
            sell.position = CGPoint(x: 8 + sellWidth / 2, y: panelTop - 24)
            heading.isHidden = true // the Sell button takes the heading's spot
            sell.addChild(makeLabel("Sell +$\(refund)"))
            towerPanel.addChild(sell)
            sellButton = sell
        }

        // MH2D-17: while a placed tower is selected, the upgrade panel takes the
        // place of the tower cards. Tapping empty map brings the cards back.
        if let selectedTower = towerManager.selected {
            panelContent = nil
            panelThumb = nil
            panelScroll = 0
            panelMaxScroll = 0
            panelViewportTop = panelTop - headerHeight + 6
            panelViewportHeight = max(1, panelViewportTop - lastSafeArea.bottom)
            buildUpgradePanel(for: selectedTower, panelTop: panelTop - headerHeight + 6, width: cardWidth)
        } else {
        // Cards live in a scrolling, clipped area under the heading.
        let viewportTop = panelTop - headerHeight + 6
        let viewportHeight = max(1, viewportTop - lastSafeArea.bottom)
        let contentHeight = CGFloat(towers.count) * (cardHeight + gap) + 8
        panelMaxScroll = max(0, contentHeight - viewportHeight)
        panelScroll = min(max(0, panelScroll), panelMaxScroll)
        panelViewportTop = viewportTop
        panelViewportHeight = viewportHeight
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: CGSize(width: panelWidth, height: viewportHeight))
        mask.position = CGPoint(x: panelWidth / 2, y: lastSafeArea.bottom + viewportHeight / 2)
        crop.maskNode = mask
        let content = SKNode()
        content.position = CGPoint(x: 0, y: panelScroll)
        crop.addChild(content)
        towerPanel.addChild(crop)
        panelContent = content
        panelThumb = nil

        for (index, tower) in towers.enumerated() {
            let enabled = towerSelection.canSelect(tower)
            let selected = towerSelection.selectedTower == tower
            let card = SKShapeNode(rectOf: CGSize(width: cardWidth, height: cardHeight), cornerRadius: 10)
            card.fillColor = enabled ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.14, alpha: 1)
            card.strokeColor = selected ? .systemYellow : UIColor(white: 0.35, alpha: 1)
            card.lineWidth = selected ? 3 : 1
            card.alpha = enabled ? 1 : 0.45
            card.position = CGPoint(
                x: 8 + cardWidth / 2 + CGFloat(index % columns) * (cardWidth + gap),
                y: panelTop - headerHeight - cardHeight / 2 - CGFloat(index / columns) * (cardHeight + gap)
            )
            // Compact card: name on top, icon + price in the middle, status below.
            let name = makeLabel(tower.displayName, size: 12)
            name.position = CGPoint(x: 0, y: cardHeight / 2 - 13)
            card.addChild(name)
            let icon = tower.makeIcon(enabled: enabled)
            icon.position = CGPoint(x: -cardWidth / 2 + 24, y: -2)
            card.addChild(icon)
            let price = makeLabel("$\(tower.cost)", size: 14)
            price.position = CGPoint(x: cardWidth * 0.18, y: -2)
            card.addChild(price)
            let status = makeLabel(enabled ? (selected ? "Selected" : "Select") : "Need $\(tower.cost - towerSelection.money)", size: 10)
            status.position = CGPoint(x: 0, y: -cardHeight / 2 + 9)
            card.addChild(status)
            if !enabled { needLabels.append((tower, status)) }
            content.addChild(card)
            towerCards.append((tower, card))
        }

        // Thin scroll bar on the panel's edge when there is more to scroll to.
        if panelMaxScroll > 0 {
            panelThumbHeight = max(24, viewportHeight * viewportHeight / (viewportHeight + panelMaxScroll))
            let thumb = SKShapeNode(rectOf: CGSize(width: 3, height: panelThumbHeight), cornerRadius: 1.5)
            thumb.fillColor = UIColor.white.withAlphaComponent(0.4)
            thumb.strokeColor = .clear
            thumb.zPosition = 5
            thumb.position.x = panelWidth - lastSafeArea.right - 3
            towerPanel.addChild(thumb)
            panelThumb = thumb
            applyPanelScroll()
        }

        if towers.isEmpty {
            let empty = makeLabel("No towers unlocked yet")
            empty.position = CGPoint(x: panelWidth / 2 - lastSafeArea.right / 2, y: size.height / 2)
            towerPanel.addChild(empty)
        }
        } // end: tower cards (no placed tower selected)

        selectionLabel.position = CGPoint(x: left, y: lastSafeArea.bottom + 12)
        if let tower = towerSelection.selectedTower {
            selectionLabel.text = "Drag to the map and release to place \(tower.displayName)"
        } else if let selectedTower = towerManager.selected {
            selectionLabel.text = "\(selectedTower.type.displayName) selected · upgrade or sell it · tap the map to close"
        } else {
            selectionLabel.text = "Drag a tower from the panel onto the map"
        }
        drawnAffordability = currentAffordability()
        debugLabel?.position = CGPoint(x: left, y: size.height - lastSafeArea.top - 24)
        updatePlacementPreview()
        setUpPath()
    }

    // MARK: - MH2D-17: Upgrade panel

    /// Draws the upgrade view in the tower panel: the tower's name and tier,
    /// current -> next numbers, and the Upgrade button (or MAX at the cap).
    /// `panelTop` is the top edge of the area under the heading.
    private func buildUpgradePanel(for tower: TowerManager.PlacedTower, panelTop: CGFloat, width: CGFloat) {
        let centerX = 8 + width / 2
        let box = SKShapeNode(rectOf: CGSize(width: width, height: 10), cornerRadius: 10) // resized below
        box.fillColor = UIColor(white: 0.18, alpha: 1)
        box.strokeColor = UIColor(white: 0.35, alpha: 1)
        box.lineWidth = 1
        towerPanel.addChild(box)

        var y = panelTop - 12

        let name = makeLabel(tower.type.displayName, size: 14)
        name.position = CGPoint(x: centerX, y: y - 6)
        towerPanel.addChild(name)
        y -= 22

        let levelsText = tower.levels.map(String.init).joined(separator: " · ")
        let tierLabel = makeLabel("Paths  \(levelsText)", size: 11)
        tierLabel.fontColor = UIColor(white: 0.75, alpha: 1)
        tierLabel.position = CGPoint(x: centerX, y: y - 4)
        towerPanel.addChild(tierLabel)
        y -= 20

        // Current -> next stats.
        for line in TowerUpgrade.statLines(for: tower.type, levels: tower.levels) {
            let title = makeLabel(line.name, size: 10)
            title.fontColor = UIColor(white: 0.65, alpha: 1)
            title.position = CGPoint(x: centerX, y: y - 5)
            towerPanel.addChild(title)
            let value: SKLabelNode
            if let next = line.next {
                value = makeLabel("\(line.current) → \(next)", size: 13)
                value.fontColor = .systemGreen
            } else {
                value = makeLabel(line.current, size: 13)
            }
            value.position = CGPoint(x: centerX, y: y - 20)
            towerPanel.addChild(value)
            y -= 30
        }
        y -= 4

        // Target priority: tap to cycle Close / Far / Front / Back.
        // (Ice pulses on everything in range and Barbed Wire lays wire, so neither picks a target.)
        if tower.type != .ice && tower.type != .trapper {
            let priorityHeight: CGFloat = 30
            let priorityButton = SKSpriteNode(color: UIColor(white: 0.3, alpha: 1),
                                              size: CGSize(width: width - 16, height: priorityHeight))
            priorityButton.position = CGPoint(x: centerX, y: y - priorityHeight / 2)
            priorityButton.addChild(makeLabel("Target: \(tower.priority.rawValue)", size: 12))
            towerPanel.addChild(priorityButton)
            self.priorityButton = priorityButton
            y -= priorityHeight + 8
        }

        // One button per upgrade path: next upgrade name + price, MAX, or LOCKED.
        let pathHeight: CGFloat = 40
        for path in 0..<TowerUpgrade.pathCount {
            let level = tower.levels[path]
            let cost = towerManager.upgradeCost(path: path)
            let canAfford = cost.map { wallet.canAfford($0) } ?? false
            let color: UIColor
            let title: String
            if let cost {
                color = canAfford ? [UIColor.systemTeal, .systemIndigo, .systemOrange][path] : UIColor(white: 0.28, alpha: 1)
                title = canAfford ? "\(TowerUpgrade.upgradeName(for: tower.type, path: path, level: level + 1)) $\(cost)"
                                  : "Need $\(cost - wallet.money)"
            } else if level >= TowerUpgrade.maxLevel {
                color = UIColor(white: 0.22, alpha: 1); title = "MAX"
            } else {
                color = UIColor(red: 0.28, green: 0.12, blue: 0.12, alpha: 1); title = "LOCKED"
            }
            let button = SKSpriteNode(color: color, size: CGSize(width: width - 16, height: pathHeight))
            button.position = CGPoint(x: centerX, y: y - pathHeight / 2)
            let top = makeLabel("\(TowerUpgrade.pathName(for: tower.type, path: path))  Lv \(level)/\(TowerUpgrade.maxLevel)", size: 9)
            top.fontColor = UIColor(white: 0.9, alpha: 1)
            top.position = CGPoint(x: 0, y: 7)
            button.addChild(top)
            let bottom = makeLabel(title, size: 11)
            bottom.position = CGPoint(x: 0, y: -10)
            if level >= TowerUpgrade.maxLevel { bottom.fontColor = .systemYellow }
            button.addChild(bottom)
            if let cost, !canAfford { upgradeNeedLabels.append((cost, bottom)) }
            towerPanel.addChild(button)
            if canAfford { upgradeButtons.append((path, button)) }
            y -= pathHeight + 4
        }
        y -= 10

        // Fit the background box around everything drawn above.
        let boxTop = panelTop
        let boxHeight = boxTop - y
        box.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -boxHeight / 2, width: width, height: boxHeight),
                          cornerWidth: 10, cornerHeight: 10, transform: nil)
        box.position = CGPoint(x: centerX, y: boxTop - boxHeight / 2)
    }

    /// Pay for and apply the selected tower's next upgrade.
    private func upgradeSelectedTower(path: Int) {
        guard let cost = towerManager.upgradeCost(path: path), wallet.canAfford(cost) else { return }
        guard towerManager.upgradeSelected(path: path) else { return }
        wallet.spend(cost)
        SoundManager.shared.play(.upgrade)
        refreshTowerPanel()         // show the new tier right away
    }

    // MARK: - Map

    /// Builds (or re-fits) the zombie route in the space left of the tower panel.
    private func setUpPath() {
        let bounds = GamePath.Bounds(
            left: lastSafeArea.left + 40,
            right: towerPanel.position.x - 40,
            bottom: lastSafeArea.bottom + 60,
            top: size.height - lastSafeArea.top - 60
        )
        // If the route moved, put existing zombies at the same spot along it.
        if let oldLanes = path.rebuild(in: bounds) {
            zombieManager.remapProgress(from: oldLanes)
        }
    }

    // These are the connection points for a future money/unlock system.
    func updatePlayerMoney(_ amount: Int) {
        wallet.set(amount)
    }

    func updateUnlockedTowers(_ towers: [TowerType]) {
        towerSelection.updateUnlockedTowers(towers)
        refreshTowerPanel()
    }

    /// Moves the cards (and the little scroll bar) to match `panelScroll`.
    private func applyPanelScroll() {
        panelContent?.position.y = panelScroll
        if let thumb = panelThumb, panelMaxScroll > 0 {
            let travel = panelViewportHeight - panelThumbHeight
            thumb.position.y = panelViewportTop - panelThumbHeight / 2 - (panelScroll / panelMaxScroll) * travel
        }
    }

    private func updatePlacementPreview() {
        placementPreview.removeAllChildren()
        guard let tower = towerSelection.selectedTower else {
            placementPreview.isHidden = true
            return
        }
        placementPreview.isHidden = false
        // Range radius of the tower being dragged.
        if !tower.spec.isGlobalRange { // global-range towers (Sniper) show no circle
            placementPreview.addChild(TowerVisuals.makeRangeRing(radius: tower.spec.range))
        }
        // No ring: the tower itself turns red when it can't go here.
        previewOutline = nil
        let previewIcon = tower.makeIcon(enabled: true)
        previewIcon.name = "previewIcon"
        placementPreview.addChild(previewIcon)
        if !isDraggingTower { // a kill can refresh the panel mid-drag; don't move the preview then
            placementPreview.position = CGPoint(x: towerPanel.position.x / 2, y: size.height / 2)
        }
        updatePreviewValidity()
    }

    // MARK: - Touch handling (drag-and-drop placement)
    //
    // Press a tower card, drag onto the map, release to place. Releasing on
    // the panel or on a red (invalid) spot cancels with no money spent.
    // Sell fires when the finger lifts on the Sell button, not on touch-down.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // After winning, the only touches that matter are the win screen buttons.
        if isWinScreenUp {
            guard let shownAt = victoryShownAt,
                  touch.timestamp - shownAt >= GameScene.gameOverTapDelay else { return }
            switch victoryOverlay?.action(at: touch.location(in: self)) {
            case .continuePlaying: continueAfterVictory()
            case .mainMenu: onMainMenuRequested?()
            case nil: break
            }
            return
        }
        // MH2D-57/82: after losing, the only touches that matter are the Game Over buttons.
        if isGameOver {
            // Don't let a tap that was already on its way when the game ended hit Retry.
            guard let shownAt = gameOverShownAt,
                  touch.timestamp - shownAt >= GameScene.gameOverTapDelay else { return }
            switch gameOverOverlay?.action(at: touch.location(in: self)) {
            case .retry: onRetryRequested?()
            case .mainMenu: onMainMenuRequested?()
            case nil: break
            }
            return
        }
        // Pause menu: only its buttons respond.
        if isPauseMenuUp {
            switch pauseOverlay?.action(at: touch.location(in: self)) {
            case .resume: setPaused(false)
            case .restart: onRetryRequested?()
            case .mainMenu: onMainMenuRequested?()
            case .toggleSound:
                SoundManager.shared.soundOn.toggle()
                SoundManager.shared.play(.tap)
                pauseOverlay?.refreshToggles()
            case .toggleMusic:
                SoundManager.shared.musicOn.toggle()
                pauseOverlay?.refreshToggles()
            case nil: break
            }
            return
        }
        if !nextWaveButton.isHidden, nextWaveButton.frame.insetBy(dx: -8, dy: -8).contains(touch.location(in: self)) {
            zombieManager.startWave()
            SoundManager.shared.play(.tap)
            updateWaveLabel()
            return
        }
        if speedButton.frame.insetBy(dx: -8, dy: -8).contains(touch.location(in: self)) {
            gameSpeed = gameSpeed == 1 ? 1.5 : 1
            worldNode.speed = CGFloat(gameSpeed) // animations keep up with the faster game
            SoundManager.shared.play(.tap)
            updateSpeedButton()
            return
        }
        if pauseButton.frame.insetBy(dx: -8, dy: -8).contains(touch.location(in: self)) {
            SoundManager.shared.play(.tap)
            setPaused(true)
            return
        }
        let point = touch.location(in: self)
        let panelPoint = touch.location(in: towerPanel)
        isDraggingTower = false
        touchStartedOnSell = false
        touchStartedOnUpgrade = false

        // Panel touches must not fall through to the map.
        if point.x >= towerPanel.position.x {
            if let priority = priorityButton, priority.contains(panelPoint) {
                towerManager.cycleSelectedPriority()
                SoundManager.shared.play(.tap)
                refreshTowerPanel()
                return
            }
            if let sell = sellButton, sell.contains(panelPoint) {
                touchStartedOnSell = true
                return
            }
            if let hit = upgradeButtons.first(where: { $0.node.contains(panelPoint) }) {
                touchStartedOnUpgrade = true
                pendingUpgradePath = hit.path
                return
            }
            // Remember where the touch began: dragging up/down scrolls the
            // panel, pulling a card to the left starts placing that tower.
            panelTouchStart = point
            panelScrollStart = panelScroll
            isScrollingPanel = false
            pendingCard = nil
            if let content = panelContent, point.y < panelViewportTop {
                let contentPoint = touch.location(in: content)
                for (tower, card) in towerCards where card.contains(contentPoint) {
                    pendingCard = tower
                }
            }
            return
        }

        // Map touch: tapping a placed tower selects it, empty map deselects.
        if towerManager.select(at: point) {
            refreshTowerPanel()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if isDraggingTower {
            movePlacementPreview(to: touch.location(in: self))
            return
        }
        guard let start = panelTouchStart else { return }
        let point = touch.location(in: self)
        let dx = point.x - start.x
        let dy = point.y - start.y

        // Pulled a card out to the left: pick up that tower.
        if !isScrollingPanel, let tower = pendingCard, dx < -10, abs(dx) > abs(dy) {
            pendingCard = nil
            panelTouchStart = nil
            if towerSelection.select(tower) { // false if it can't be afforded
                towerManager.deselect()        // picking a card leaves "tower selected" mode
                isDraggingTower = true
                refreshTowerPanel()            // shows the preview
                movePlacementPreview(to: point)
            }
            return
        }

        // Otherwise an up/down drag scrolls the panel.
        if isScrollingPanel || abs(dy) > 8 {
            isScrollingPanel = true
            pendingCard = nil
            panelScroll = min(max(0, panelScrollStart + dy), panelMaxScroll)
            applyPanelScroll()
        }
    }

    /// Release: place the tower if the finger is over the map and the spot
    /// is valid; otherwise cancel the drag.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOver, !isWinScreenUp, !isPauseMenuUp else { return }
        guard let touch = touches.first else { return }
        panelTouchStart = nil
        pendingCard = nil
        isScrollingPanel = false

        if isDraggingTower {
            isDraggingTower = false
            let releasePoint = touch.location(in: self)
            // Use the final finger position, even if no "moved" events arrived.
            movePlacementPreview(to: releasePoint)
            if releasePoint.x < towerPanel.position.x {
                placeTower(at: placementPreview.position)
            }
            if towerSelection.isPlacementMode { // released on panel or invalid spot
                towerSelection.cancel()
                refreshTowerPanel()
            }
            return
        }

        if touchStartedOnUpgrade {
            touchStartedOnUpgrade = false
            if let path = pendingUpgradePath,
               let pressed = upgradeButtons.first(where: { $0.path == path }),
               pressed.node.contains(touch.location(in: towerPanel)) {
                upgradeSelectedTower(path: path)
            }
            pendingUpgradePath = nil
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
        touchStartedOnUpgrade = false
        panelTouchStart = nil
        pendingCard = nil
        isScrollingPanel = false
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

    /// The dragged tower looks normal where it can be placed and turns
    /// completely red where it can't.
    /// Every shape drawn anywhere inside a node (the tower's base and top).
    private func allShapes(in node: SKNode) -> [SKShapeNode] {
        var shapes: [SKShapeNode] = []
        for child in node.children {
            if let shape = child as? SKShapeNode { shapes.append(shape) }
            shapes += allShapes(in: child)
        }
        return shapes
    }

    private func updatePreviewValidity() {
        let valid = towerManager.isValidPlacement(at: placementPreview.position, type: towerSelection.selectedTower)
        guard let icon = placementPreview.childNode(withName: "previewIcon") else { return }
        for piece in allShapes(in: icon) {
            // Remember the tower's real colors the first time so they can be restored.
            if piece.userData == nil { piece.userData = NSMutableDictionary() }
            if piece.userData?["fill"] == nil {
                piece.userData?["fill"] = piece.fillColor
                piece.userData?["stroke"] = piece.strokeColor
            }
            if valid {
                piece.fillColor = piece.userData?["fill"] as? UIColor ?? piece.fillColor
                piece.strokeColor = piece.userData?["stroke"] as? UIColor ?? piece.strokeColor
            } else {
                piece.fillColor = .systemRed
                piece.strokeColor = UIColor(red: 0.45, green: 0.05, blue: 0.05, alpha: 1)
            }
        }
    }

    // MARK: - Buying and selling towers (money lives here; rules live in TowerManager)

    private func placeTower(at point: CGPoint) {
        guard let type = towerSelection.selectedTower,
              towerSelection.canSelect(type),
              towerManager.place(type, at: point) else { return } // rejected: nothing placed, no money spent

        // Pay, leave placement mode, and refresh the panel (money, card states).
        wallet.spend(type.cost)
        SoundManager.shared.play(.place)
        towerSelection.cancel()
        refreshTowerPanel()
    }

    /// Remove the selected tower, refund part of its cost, free its spot.
    private func sellSelectedTower() {
        guard let refund = towerManager.sellSelected() else { return }
        wallet.add(refund)
        SoundManager.shared.play(.sell)
        refreshTowerPanel()         // back to the tower cards right away
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
        if panelDirty, currentTime - lastPanelRefreshTime >= panelRefreshInterval {
            lastPanelRefreshTime = currentTime
            refreshTowerPanel() // clears panelDirty
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

        accumulator += frameDelta * gameSpeed

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
        guard !isGameOver, !isWinScreenUp, !isPauseMenuUp else { return } // MH2D-57: freeze everything on Game Over (and on the win screen)
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
        guard !isGameOver else { return } // base just fell: don't count this wave as survived
        towerManager.updateFire(deltaTime: deltaTime)   // MH2D-12 TEMP test shooters
        projectileSystem.update(deltaTime: deltaTime, bounds: size) // MH2D-46 collision checks

        tickCount += 1
        updateDebugStats()
        zombieManager.checkWaveCompletion()
        updateWaveLabel()
    }

    /// "Wave 12/40", or just "Wave 41" once the player has continued past the last wave.
    private func updateWaveLabel() {
        nextWaveButton.isHidden = zombieManager.isWaveActive || isGameOver || isWinScreenUp
        let bossRound = WaveDefinition.isBossWave(zombieManager.currentWave)
        nextWaveLabel.text = bossRound ? "Start Boss Wave \(zombieManager.currentWave)" : "Start Wave \(zombieManager.currentWave)"
        if zombieManager.currentWave > zombieManager.totalWaves {
            waveLabel.text = "Wave \(zombieManager.currentWave)"
        } else {
            waveLabel.text = "Wave \(zombieManager.currentWave)/\(zombieManager.totalWaves)"
        }
        if bossRound { waveLabel.text = "BOSS · " + (waveLabel.text ?? "") }
    }

    // MARK: - Win screen

    /// The last wave has been cleared: freeze the game and show the win screen.
    private func showVictory() {
        guard !isGameOver, !isWinScreenUp else { return }
        isWinScreenUp = true
        SoundManager.shared.play(.win)
        // Drop any tower the player is dragging so it can't build or charge.
        if isDraggingTower {
            isDraggingTower = false
            towerSelection.cancel()
            refreshTowerPanel()
        }
        placementPreview.isHidden = true

        let overlay = VictoryOverlay(size: size,
                                     totalWaves: zombieManager.totalWaves,
                                     livesLeft: baseHealth.current,
                                     showsMainMenu: onMainMenuRequested != nil)
        victoryOverlay = overlay
        victoryShownAt = ProcessInfo.processInfo.systemUptime
        addChild(overlay)
    }

    /// Win screen -> Continue: keep playing; the waves keep coming.
    private func continueAfterVictory() {
        victoryOverlay?.removeFromParent()
        victoryOverlay = nil
        isWinScreenUp = false
        zombieManager.continueAfterVictory()
        updateWaveLabel()
        refreshTowerPanel() // also resets the drag preview
    }

    // MARK: - Game Over (MH2D-57)

    /// Stop the game and show the Game Over screen (MH2D-81).
    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        SoundManager.shared.play(.gameOver)
        // Drop any tower the player is dragging so releasing it can't build or charge.
        if isDraggingTower {
            isDraggingTower = false
            towerSelection.cancel()
            refreshTowerPanel()
        }
        placementPreview.isHidden = true

        let overlay = GameOverOverlay(size: size,
                                      wavesSurvived: runStats.wavesSurvived,
                                      totalWaves: zombieManager.totalWaves,
                                      showsMainMenu: onMainMenuRequested != nil)
        gameOverOverlay = overlay
        gameOverShownAt = ProcessInfo.processInfo.systemUptime
        addChild(overlay)
    }

    /// Pause button: freezes the game (and the zombie animations) and shows the pause menu.
    private func updateSpeedButton() {
        speedLabel.text = gameSpeed == 1 ? "1×" : "1.5×"
        speedButton.fillColor = gameSpeed == 1 ? SKColor(white: 0, alpha: 0.45)
                                               : SKColor.systemOrange.withAlphaComponent(0.85)
    }

    private func setPaused(_ paused: Bool) {
        if paused {
            guard pauseOverlay == nil else { return }
            // Drop anything half-done (a tower being dragged) so it can't be placed while paused.
            touchesCancelled([], with: nil)
            let overlay = PauseOverlay(size: size)
            addChild(overlay)
            pauseOverlay = overlay
            worldNode.isPaused = true
        } else {
            pauseOverlay?.removeFromParent()
            pauseOverlay = nil
            worldNode.isPaused = false
            accumulator = 0
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        refreshTowerPanel()
        // Rebuild the pause menu for the new screen size (iPad, rotation, split view).
        if pauseOverlay != nil {
            pauseOverlay?.removeFromParent()
            let overlay = PauseOverlay(size: size)
            addChild(overlay)
            pauseOverlay = overlay
        }
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
        debugLabel?.text = "ticks \(tickCount) | zombies \(zombieManager.zombies.count) | shots \(projectileSystem.activeCount) | hits \(projectileSystem.hitCount) | misses \(projectileSystem.missCount) | breached \(zombieManager.breachCount)"
    }
}
