//
//  TowerManager.swift
//  Towers
//
//  Owns placed towers: where they can go, placing, selecting, selling, and
//  their (TEMP) firing. MH2D-9 (Adam) replaces the targeting in `updateFire`.
//

import SpriteKit
import UIKit

final class TowerManager {

    struct PlacedTower {
        let type: TowerType
        let node: SKNode
    }

    /// The area of the map where towers may be placed.
    struct Playfield {
        var minX: CGFloat = 0
        var maxX: CGFloat = 0
        var minY: CGFloat = 0
        var maxY: CGFloat = 0

        func contains(_ p: CGPoint) -> Bool {
            p.y > minY && p.y < maxY && p.x > minX && p.x < maxX
        }
    }

    static let radius: CGFloat = 22
    static let gap: CGFloat = 6        // min empty space between towers
    static let sellRefundRate: Double = 0.7

    private(set) var placed: [PlacedTower] = []
    private(set) var selectedIndex: Int?
    /// Set by the scene whenever the layout changes.
    var playfield = Playfield()

    private var fireTimers: [ObjectIdentifier: TimeInterval] = [:]

    private let world: SKNode
    private let path: GamePath
    private let zombies: ZombieManager
    private let projectiles: ProjectileSystem

    init(world: SKNode, path: GamePath, zombies: ZombieManager, projectiles: ProjectileSystem) {
        self.world = world
        self.path = path
        self.zombies = zombies
        self.projectiles = projectiles
    }

    var selected: PlacedTower? {
        guard let index = selectedIndex, placed.indices.contains(index) else { return nil }
        return placed[index]
    }

    // MARK: Placement (MH2D-8)

    /// A spot is valid if it is on the map, clear of the path edge, and
    /// doesn't overlap an already placed tower.
    func isValidPlacement(at point: CGPoint) -> Bool {
        guard playfield.contains(point) else { return false }
        if path.distance(from: point) < GamePath.halfWidth + TowerManager.radius { return false }
        for tower in placed {
            let d = hypot(point.x - tower.node.position.x, point.y - tower.node.position.y)
            if d < TowerManager.radius * 2 + TowerManager.gap { return false }
        }
        return true
    }

    /// Builds the tower on the map. Returns false (and does nothing) if the
    /// spot is invalid. The caller handles payment.
    @discardableResult
    func place(_ type: TowerType, at point: CGPoint) -> Bool {
        guard isValidPlacement(at: point) else { return false }

        let node = SKNode()
        node.name = "tower"
        node.position = point
        node.zPosition = Layer.towers.rawValue

        let base = SKShapeNode(circleOfRadius: TowerManager.radius)
        base.fillColor = type.color.withAlphaComponent(0.25)
        base.strokeColor = type.color
        base.lineWidth = 2
        node.addChild(base)
        node.addChild(type.makeIcon(enabled: true))
        // MH2D-12: shows the tower's range when the hitbox overlay is on.
        node.addChild(DebugOverlay.makeCircle(radius: type.spec.range,
                                              color: UIColor.white.withAlphaComponent(0.5),
                                              name: "rangeDebug"))

        world.addChild(node)
        placed.append(PlacedTower(type: type, node: node))
        return true
    }

    // MARK: Selling / selecting

    static func sellValue(of type: TowerType) -> Int {
        Int((Double(type.cost) * sellRefundRate).rounded())
    }

    func deselect() {
        if let tower = selected {
            tower.node.childNode(withName: "selectionRing")?.removeFromParent()
            tower.node.childNode(withName: "rangeRing")?.removeFromParent()
        }
        selectedIndex = nil
    }

    /// Select the placed tower under the touch (if any); otherwise deselect.
    /// Returns true if the selection changed.
    func select(at point: CGPoint) -> Bool {
        let hit = placed.firstIndex {
            hypot(point.x - $0.node.position.x, point.y - $0.node.position.y) <= TowerManager.radius + 10
        }
        guard hit != selectedIndex else { return false }
        deselect()
        if let hit {
            selectedIndex = hit
            let ring = SKShapeNode(circleOfRadius: TowerManager.radius + 5)
            ring.name = "selectionRing"
            ring.strokeColor = .systemYellow
            ring.lineWidth = 3
            placed[hit].node.addChild(ring)
            // Show how far this tower can shoot while it's selected.
            placed[hit].node.addChild(TowerVisuals.makeRangeRing(radius: placed[hit].type.spec.range))
        }
        return true
    }

    /// Removes the selected tower and frees its spot. Returns its type so
    /// the caller can pay the refund, or nil if nothing was selected.
    func sellSelected() -> TowerType? {
        guard let index = selectedIndex, placed.indices.contains(index) else { return nil }
        let sold = placed.remove(at: index)
        fireTimers.removeValue(forKey: ObjectIdentifier(sold.node))
        sold.node.removeFromParent()
        selectedIndex = nil
        return sold.type
    }

    // MARK: Firing (TEMP until MH2D-9)

    /// TEMP test shooter: each placed tower fires at the nearest zombie in
    /// range; the ice tower pulses a slow on everything in range.
    func updateFire(deltaTime: TimeInterval) {
        for tower in placed {
            let spec = tower.type.spec
            let key = ObjectIdentifier(tower.node)
            let timer = (fireTimers[key] ?? 0) + deltaTime
            guard timer >= spec.fireInterval else {
                fireTimers[key] = timer
                continue
            }

            let all = zombies.zombies

            // Ice tower: area slow pulse on everything in range. No damage.
            if tower.type == .ice {
                var slowedAny = false
                for i in all.indices {
                    let d = hypot(all[i].node.position.x - tower.node.position.x,
                                  all[i].node.position.y - tower.node.position.y)
                    if d <= spec.range {
                        zombies.slow(at: i, duration: ZombieManager.iceSlowDuration)
                        slowedAny = true
                    }
                }
                guard slowedAny else {
                    fireTimers[key] = spec.fireInterval // ready; waits for a target
                    continue
                }
                fireTimers[key] = 0
                showFrostPulse(at: tower.node.position, radius: spec.range, color: spec.color)
                continue
            }

            var nearest: (index: Int, distance: CGFloat)?
            for (i, zombie) in all.enumerated() {
                let d = hypot(zombie.node.position.x - tower.node.position.x,
                              zombie.node.position.y - tower.node.position.y)
                if d <= spec.range, d < (nearest?.distance ?? .greatestFiniteMagnitude) {
                    nearest = (i, d)
                }
            }
            guard let target = nearest else {
                fireTimers[key] = spec.fireInterval // ready; waits for a target
                continue
            }
            fireTimers[key] = 0
            projectiles.fire(from: tower.node.position, at: all[target.index], spec: spec)
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
        world.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 1, duration: 0.35), .fadeOut(withDuration: 0.35)]),
            .removeFromParent()
        ]))
    }
}
