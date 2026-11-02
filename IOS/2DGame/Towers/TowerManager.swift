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
        /// MH2D-17: how many times this tower has been upgraded (0...TowerUpgrade.maxTier).
        var tier = 0

        /// This tower's numbers, including its upgrades.
        var spec: ProjectileSpec { TowerUpgrade.spec(for: type, tier: tier) }
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
    /// Which way each tower last aimed (a unit vector), used for gun recoil.
    private var aimDirections: [ObjectIdentifier: CGVector] = [:]

    /// A patch of barbed wire on the road. It damages zombies that walk onto
    /// it and wears out: each zombie that hits it uses up 1 durability.
    private struct Wire {
        let node: SKShapeNode
        let position: CGPoint
        let owner: ObjectIdentifier
        var durability: Int
        let maxDurability: Int
        let damage: Int
        var touching: Set<ObjectIdentifier> = []
    }
    private var wires: [Wire] = []
    static let wiresPerTower = 3
    static let wireSpacing: CGFloat = 30   // min gap between two patches
    static let wireReach: CGFloat = 14     // how close a zombie must be to hit the wire

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

        // No ring around placed towers: just the tower itself. Its range ring
        // only shows while it is selected (see select(at:)).
        let icon = type.makeIcon(enabled: true)
        icon.name = "towerIcon"
        node.addChild(icon)
        // Idle: the survivor breathes (a slow, tiny squash and stretch). Each
        // tower starts at a different moment so they don't move in sync.
        icon.childNode(withName: "towerTop")?.run(.sequence([
            .wait(forDuration: Double.random(in: 0...1.2)),
            .repeatForever(.sequence([
                .scaleY(to: 1.04, duration: 0.7),
                .scaleY(to: 0.97, duration: 0.7)
            ]))
        ]), withKey: "idle")
        // MH2D-12: shows the tower's range when the hitbox overlay is on.
        node.addChild(DebugOverlay.makeCircle(radius: type.spec.range,
                                              color: UIColor.white.withAlphaComponent(0.5),
                                              name: "rangeDebug"))

        world.addChild(node)
        placed.append(PlacedTower(type: type, node: node))
        return true
    }

    // MARK: Selling / selecting

    /// A tower sells for part of everything spent on it, upgrades included.
    static func sellValue(of tower: PlacedTower) -> Int {
        Int((Double(TowerUpgrade.moneySpent(on: tower.type, tier: tower.tier)) * sellRefundRate).rounded())
    }

    // MARK: Upgrading (MH2D-17)

    /// What the next upgrade of the selected tower costs, or nil if nothing is
    /// selected or it is already at the top tier.
    var upgradeCost: Int? {
        guard let tower = selected, tower.tier < TowerUpgrade.maxTier else { return nil }
        return TowerUpgrade.cost(of: tower.type, toTier: tower.tier + 1)
    }

    /// Raises the selected tower one tier (the scene has already taken the
    /// money). Returns false if nothing is selected or it is at the cap.
    @discardableResult
    func upgradeSelected() -> Bool {
        guard let index = selectedIndex, placed.indices.contains(index),
              placed[index].tier < TowerUpgrade.maxTier else { return false }
        placed[index].tier += 1
        let tower = placed[index]
        // Range ring grows with the range.
        tower.node.childNode(withName: "rangeRing")?.removeFromParent()
        tower.node.addChild(TowerVisuals.makeRangeRing(radius: tower.spec.range))
        showTierPips(on: tower)
        // A little pop so the upgrade is noticeable.
        let icon = tower.node.childNode(withName: "towerIcon")
        icon?.removeAction(forKey: "upgradePop")
        icon?.run(.sequence([.scale(to: 1.25, duration: 0.1), .scale(to: 1.0, duration: 0.15)]), withKey: "upgradePop")
        DamageEffects.puff(at: tower.node.position, radius: 10, color: .systemYellow,
                           startScale: 0.5, endScale: 2.2, duration: 0.35, stroke: .systemYellow, in: world)
        return true
    }

    /// Small yellow dots over the tower: one per tier.
    private func showTierPips(on tower: PlacedTower) {
        tower.node.childNode(withName: "tierPips")?.removeFromParent()
        guard tower.tier > 0 else { return }
        let pips = SKNode()
        pips.name = "tierPips"
        pips.zPosition = 200
        let spacing: CGFloat = 7
        for i in 0..<tower.tier {
            let dot = SKShapeNode(circleOfRadius: 2.5)
            dot.fillColor = .systemYellow
            dot.strokeColor = UIColor(white: 0.1, alpha: 1)
            dot.lineWidth = 1
            dot.position = CGPoint(x: (CGFloat(i) - CGFloat(tower.tier - 1) / 2) * spacing, y: 0)
            pips.addChild(dot)
        }
        pips.position = CGPoint(x: 0, y: TowerManager.radius + 12)
        tower.node.addChild(pips)
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
            placed[hit].node.addChild(TowerVisuals.makeRangeRing(radius: placed[hit].spec.range))
        }
        return true
    }

    /// Removes the selected tower and frees its spot. Returns its type so
    /// the caller can pay the refund, or nil if nothing was selected.
    func sellSelected() -> Int? {
        guard let index = selectedIndex, placed.indices.contains(index) else { return nil }
        let sold = placed.remove(at: index)
        let soldKey = ObjectIdentifier(sold.node)
        fireTimers.removeValue(forKey: soldKey)
        aimDirections.removeValue(forKey: soldKey)
        // A sold barbed-wire tower takes its wire with it.
        wires.removeAll { wire in
            guard wire.owner == soldKey else { return false }
            wire.node.removeFromParent()
            return true
        }
        sold.node.removeFromParent()
        selectedIndex = nil
        return TowerManager.sellValue(of: sold)
    }

    // MARK: Firing (TEMP until MH2D-9)

    /// TEMP test shooter: each placed tower fires at the nearest zombie in
    /// range; the ice tower pulses a slow on everything in range.
    func updateFire(deltaTime: TimeInterval) {
        updateWires()
        for tower in placed {
            let spec = tower.spec
            let key = ObjectIdentifier(tower.node)

            // Swing the gun around to face the nearest zombie in range.
            if tower.type.turnsToAim {
                var closest: (position: CGPoint, distance: CGFloat)?
                for zombie in zombies.zombies {
                    let d = hypot(zombie.node.position.x - tower.node.position.x,
                                  zombie.node.position.y - tower.node.position.y)
                    if d <= spec.range, d < (closest?.distance ?? .greatestFiniteMagnitude) {
                        closest = (zombie.node.position, d)
                    }
                }
                if let target = closest { aim(tower, at: target.position) }
            }
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
                        DamageEffects.showImpact(.frost, at: all[i].node.position, radius: 14, in: world)
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

            // Barbed wire tower: lays a patch of wire on the road in range.
            if tower.type == .trapper {
                guard placeWire(for: tower, spec: spec) else {
                    fireTimers[key] = spec.fireInterval // ready; waits for room / a free slot
                    continue
                }
                fireTimers[key] = 0
                continue
            }

            // Tesla: lightning hits the nearest zombie and jumps to the next ones.
            if spec.chainCount > 0 {
                var first: (index: Int, distance: CGFloat)?
                for (i, zombie) in all.enumerated() {
                    let d = hypot(zombie.node.position.x - tower.node.position.x,
                                  zombie.node.position.y - tower.node.position.y)
                    if d <= spec.range, d < (first?.distance ?? .greatestFiniteMagnitude) {
                        first = (i, d)
                    }
                }
                guard let start = first else {
                    fireTimers[key] = spec.fireInterval
                    continue
                }
                fireTimers[key] = 0

                var chain = [start.index]
                var current = all[start.index].node.position
                while chain.count < spec.chainCount {
                    var next: Int?
                    var best = spec.chainRange
                    for (i, zombie) in all.enumerated() where !chain.contains(i) {
                        let d = hypot(zombie.node.position.x - current.x, zombie.node.position.y - current.y)
                        if d <= best { best = d; next = i }
                    }
                    guard let n = next else { break }
                    chain.append(n)
                    current = all[n].node.position
                }

                let points = chain.map { all[$0].node.position }
                showLightning(through: [tower.node.position] + points)
                for p in points {
                    DamageEffects.showImpact(spec.damageType, at: p, radius: 0, in: world)
                }
                // Highest index first so a kill never shifts a zombie we haven't hit yet.
                for i in chain.sorted(by: >) {
                    zombies.applyDamage(at: i, damage: spec.damage, type: spec.damageType)
                }
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
            if !tower.type.turnsToAim { aimDirections[key] = CGVector(dx: 0, dy: 1) }
            recoil(tower)
        }
    }

    /// Points a tower's gun at a spot. A target on the left mirrors the tower
    /// so the survivor stays upright, and the gun tilts up or down toward the
    /// target (limited so the survivor never tips over).
    private func aim(_ tower: PlacedTower, at target: CGPoint) {
        // Only the top (gun and survivor) swings around; the base stays still.
        guard let top = tower.node.childNode(withName: "towerIcon")?.childNode(withName: "towerTop") else { return }
        // Some towers (the Sniper) have a separate gun, so the person stays put.
        let icon = top.childNode(withName: "towerGun") ?? top
        let dx = target.x - tower.node.position.x
        let dy = target.y - tower.node.position.y
        // A mortar doesn't swing around: its tube just leans toward the target.
        if tower.type == .grenadier {
            let lean = max(-0.7, min(0.7, dx / 60 * 0.7))
            aimDirections[ObjectIdentifier(tower.node)] = CGVector(dx: 0, dy: 1)
            icon.removeAction(forKey: "aim")
            icon.run(.rotate(toAngle: -lean, duration: 0.2, shortestUnitArc: true), withKey: "aim")
            return
        }
        let facingLeft = dx < 0
        let tilt = max(-0.9, min(0.9, atan2(dy, abs(dx))))
        let length = max(1, hypot(dx, dy))
        aimDirections[ObjectIdentifier(tower.node)] = CGVector(dx: dx / length, dy: dy / length)
        // The survivor turns around to face a target on the left (more than
        // 90 degrees from where he normally faces).
        top.xScale = facingLeft ? -1 : 1
        icon.removeAction(forKey: "aim")
        if icon !== top {
            // Separate gun: the person stays upright, only the gun tilts.
            // (The mirrored top already points the gun the right way.)
            icon.run(.rotate(toAngle: tilt, duration: 0.08, shortestUnitArc: true), withKey: "aim")
        } else {
            // No separate gun (the Turret): the whole top tilts.
            icon.run(.rotate(toAngle: facingLeft ? -tilt : tilt, duration: 0.08, shortestUnitArc: true), withKey: "aim")
        }
    }

    /// Kick the whole tower back a few points when it fires, then settle.
    /// (The Flamer just keeps burning, so it doesn't kick.)
    private func recoil(_ tower: PlacedTower) {
        guard tower.type != .flamethrower,
              let top = tower.node.childNode(withName: "towerIcon")?.childNode(withName: "towerTop"),
              let aimed = aimDirections[ObjectIdentifier(tower.node)] else { return }
        // A mortar recoils straight down its tube; other guns kick back along the aim.
        var dir = tower.type == .grenadier ? CGVector(dx: 0, dy: 1) : aimed
        // A gun inside the (mirrored) top moves in the top's own left/right,
        // which always points toward the target.
        if top.childNode(withName: "towerGun") != nil, tower.type != .grenadier {
            dir = CGVector(dx: abs(dir.dx), dy: dir.dy)
        }
        let strength: CGFloat = tower.type == .sniper ? 5 : (tower.type == .grenadier ? 4 : 2.5)
        let part = top.childNode(withName: "towerGun") ?? top
        let home = part.userData?["home"] as? NSValue
        let rest = home?.cgPointValue ?? part.position
        if home == nil { // remember where the part normally sits
            part.userData = part.userData ?? NSMutableDictionary()
            part.userData?["home"] = NSValue(cgPoint: part.position)
        }
        part.run(.sequence([
            .move(to: CGPoint(x: rest.x - dir.dx * strength, y: rest.y - dir.dy * strength), duration: 0.04),
            .move(to: rest, duration: 0.12)
        ]), withKey: "recoil")
    }

    // MARK: Barbed wire

    /// Puts one patch of wire on the road, at the point in range that is
    /// furthest along the route and not too close to other wire. Returns
    /// false if this tower already has its patches out or there is no room.
    private func placeWire(for tower: PlacedTower, spec: ProjectileSpec) -> Bool {
        let owner = ObjectIdentifier(tower.node)
        guard wires.filter({ $0.owner == owner }).count < TowerManager.wiresPerTower else { return false }

        var best: (point: CGPoint, angle: CGFloat)?
        let points = path.waypoints
        guard points.count >= 2 else { return false }
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { continue }
            let steps = max(1, Int(length / 6))
            for s in 0...steps {
                let t = min(1, CGFloat(s) * 6 / length)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                guard hypot(p.x - tower.node.position.x, p.y - tower.node.position.y) <= spec.range else { continue }
                guard !wires.contains(where: { hypot(p.x - $0.position.x, p.y - $0.position.y) < TowerManager.wireSpacing }) else { continue }
                best = (p, atan2(b.y - a.y, b.x - a.x)) // later points win = further along the route
            }
        }
        guard let spot = best else { return false }

        // Zig-zag coil across the road: a thick dark outline with a bright
        // metal wire on top and spiky barbs, so it stands out on the dirt.
        let width: CGFloat = 32
        let height: CGFloat = 8
        let zigzag = CGMutablePath()
        let barbs = CGMutablePath()
        zigzag.move(to: CGPoint(x: -width / 2, y: 0))
        var x = -width / 2
        var up = true
        while x < width / 2 {
            x = min(x + 4, width / 2)
            let y = up ? height : -height
            zigzag.addLine(to: CGPoint(x: x, y: y))
            // A little barb sticking out at each bend.
            barbs.move(to: CGPoint(x: x - 2, y: y))
            barbs.addLine(to: CGPoint(x: x + 2, y: y + (up ? 3 : -3)))
            barbs.move(to: CGPoint(x: x + 2, y: y))
            barbs.addLine(to: CGPoint(x: x - 2, y: y + (up ? 3 : -3)))
            up.toggle()
        }
        let node = SKShapeNode(path: zigzag)
        node.strokeColor = UIColor(white: 0.12, alpha: 1)
        node.lineWidth = 4.5
        node.lineJoin = .round
        node.position = spot.point
        node.zRotation = spot.angle + .pi / 2 // across the road
        node.zPosition = Layer.path.rawValue + 1

        let metal = SKShapeNode(path: zigzag)
        metal.strokeColor = UIColor(white: 0.92, alpha: 1)
        metal.lineWidth = 2
        metal.lineJoin = .round
        node.addChild(metal)

        let barbShape = SKShapeNode(path: barbs)
        barbShape.strokeColor = UIColor(white: 0.12, alpha: 1)
        barbShape.lineWidth = 1.5
        node.addChild(barbShape)

        // Two fence posts at the ends.
        for end: CGFloat in [-width / 2, width / 2] {
            let post = SKShapeNode(circleOfRadius: 2.5)
            post.fillColor = UIColor(red: 0.45, green: 0.30, blue: 0.15, alpha: 1)
            post.strokeColor = UIColor(white: 0.12, alpha: 1)
            post.lineWidth = 1
            post.position = CGPoint(x: end, y: 0)
            node.addChild(post)
        }
        world.addChild(node)

        wires.append(Wire(node: node, position: spot.point, owner: owner, durability: spec.wireDurability,
                          maxDurability: max(1, spec.wireDurability), damage: spec.damage))
        return true
    }

    /// Each zombie that steps onto a patch takes 1 damage and wears the wire
    /// down by 1. A worn patch fades, and disappears when used up.
    private func updateWires() {
        guard !wires.isEmpty else { return }
        for w in wires.indices.reversed() {
            var wire = wires[w]
            let all = zombies.zombies
            var nowTouching: Set<ObjectIdentifier> = []
            var newHits: [Int] = []
            for (i, zombie) in all.enumerated() {
                let d = hypot(zombie.node.position.x - wire.position.x, zombie.node.position.y - wire.position.y)
                if d <= TowerManager.wireReach + ZombieManager.radius {
                    let id = ObjectIdentifier(zombie.node)
                    nowTouching.insert(id)
                    if !wire.touching.contains(id) { newHits.append(i) }
                }
            }
            for i in newHits.sorted(by: >) {
                guard wire.durability > 0 else { break }
                zombies.applyDamage(at: i, damage: wire.damage, type: .trap)
                wire.durability -= 1
                DamageEffects.showImpact(.trap, at: wire.position, radius: 0, in: world)
            }
            wire.touching = nowTouching
            if wire.durability <= 0 {
                wire.node.removeFromParent()
                wires.remove(at: w)
            } else {
                wire.node.alpha = 0.55 + 0.45 * CGFloat(wire.durability) / CGFloat(wire.maxDurability)
                wires[w] = wire
            }
        }
    }

    // MARK: Lightning (Tesla)

    /// Jagged bolt through the given points; fades out quickly.
    private func showLightning(through points: [CGPoint]) {
        guard points.count >= 2 else { return }
        let bolt = CGMutablePath()
        bolt.move(to: points[0])
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let mid = CGPoint(x: (a.x + b.x) / 2 + CGFloat.random(in: -6...6),
                              y: (a.y + b.y) / 2 + CGFloat.random(in: -6...6))
            bolt.addLine(to: mid)
            bolt.addLine(to: b)
        }
        let node = SKShapeNode(path: bolt)
        node.strokeColor = DamageType.electric.effectColor
        node.lineWidth = 2.5
        node.zPosition = Layer.projectiles.rawValue
        world.addChild(node)
        node.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))

        // Bright white core on top, and a flash at the top of the coil.
        let core = SKShapeNode(path: bolt)
        core.strokeColor = .white
        core.lineWidth = 1
        core.zPosition = Layer.projectiles.rawValue + 1
        world.addChild(core)
        core.run(.sequence([.fadeOut(withDuration: 0.14), .removeFromParent()]))
        DamageEffects.puff(at: CGPoint(x: points[0].x + 5, y: points[0].y + 13), radius: 9,
                           color: DamageType.electric.effectColor, startScale: 0.5, endScale: 1.5,
                           duration: 0.2, in: world)
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
        // A burst of snowflakes blowing outward with the pulse.
        for k in 0..<14 {
            let angle = CGFloat(k) / 14 * 2 * .pi + CGFloat.random(in: -0.2...0.2)
            let flake = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...2.5))
            flake.fillColor = .white
            flake.strokeColor = .clear
            flake.position = position
            flake.zPosition = Layer.projectiles.rawValue
            world.addChild(flake)
            let reach = radius * CGFloat.random(in: 0.6...1.0)
            flake.run(.sequence([
                .group([.moveBy(x: cos(angle) * reach, y: sin(angle) * reach - 6, duration: 0.5),
                        .fadeOut(withDuration: 0.5)]),
                .removeFromParent()
            ]))
        }
    }
}
