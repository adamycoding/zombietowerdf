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

    /// Which zombie a tower picks when several are in range.
    enum TargetPriority: String, CaseIterable {
        case close = "Close"   // nearest to the tower
        case far = "Far"       // furthest from the tower (still in range)
        case front = "Front"   // furthest along the road (closest to the base)
        case back = "Back"     // least far along the road (just came in)

        var next: TargetPriority {
            let all = TargetPriority.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    struct PlacedTower {
        let type: TowerType
        let node: SKNode
        var priority: TargetPriority = .close
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

    /// Size of a tower's footprint for placement: roughly the drawn tower, so a
    /// tower can go anywhere its picture doesn't touch a road, rock or another tower.
    static let radius: CGFloat = 12    // fallback / screen-edge margin (half the 24pt icon)
    static let gap: CGFloat = 1        // empty space left between two towers (they never quite touch)
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
    func isValidPlacement(at point: CGPoint, type: TowerType? = nil) -> Bool {
        let box = type.map { footprint(of: $0) }
            ?? CGRect(x: -TowerManager.radius, y: -TowerManager.radius, width: TowerManager.radius * 2, height: TowerManager.radius * 2)
        let mine = box.offsetBy(dx: point.x, dy: point.y)

        // The drawn tower must stay inside the map (it may touch the very edge).
        guard mine.minX >= playfield.minX, mine.maxX <= playfield.maxX,
              mine.minY >= playfield.minY, mine.maxY <= playfield.maxY else { return false }

        // The road's drawn edge is 3 points wider than the road itself. Check a grid of
        // points over the tower's drawing against it.
        let clearance = GamePath.halfWidth + 3
        for i in 0...4 {
            for j in 0...4 {
                let p = CGPoint(x: mine.minX + mine.width * CGFloat(i) / 4, y: mine.minY + mine.height * CGFloat(j) / 4)
                if path.distance(from: p) < clearance { return false }
            }
        }
        // Trees, rocks and boulders: the drawing must not reach into them.
        for o in path.obstacles {
            let nx = min(max(o.center.x, mine.minX), mine.maxX)
            let ny = min(max(o.center.y, mine.minY), mine.maxY)
            if hypot(o.center.x - nx, o.center.y - ny) < o.radius { return false }
        }
        // Two towers may sit right next to each other, but their drawings must not touch.
        for tower in placed {
            let other = footprint(of: tower.type).offsetBy(dx: tower.node.position.x, dy: tower.node.position.y)
            if mine.insetBy(dx: -TowerManager.gap / 2, dy: -TowerManager.gap / 2)
                .intersects(other.insetBy(dx: -TowerManager.gap / 2, dy: -TowerManager.gap / 2)) { return false }
        }
        return true
    }

    /// Picks the zombie this tower shoots: it must be in range and in view, then the
    /// tower's priority decides (Close / Far / Front / Back).
    private func pickTarget(for tower: PlacedTower, spec: ProjectileSpec, in all: [ZombieManager.Zombie]) -> Int? {
        let origin = tower.node.position
        var best: (index: Int, score: CGFloat)?
        for (i, zombie) in all.enumerated() {
            let p = zombie.node.position
            let d = hypot(p.x - origin.x, p.y - origin.y)
            guard d <= spec.range,
                  !spec.isGlobalRange || playfield.contains(p),
                  !path.isBlocked(from: origin, to: p) else { continue }
            // Lower score wins.
            let score: CGFloat
            switch tower.priority {
            case .close: score = d
            case .far: score = -d
            case .front: score = zombies.remainingDistance(of: zombie)
            case .back: score = -zombies.remainingDistance(of: zombie)
            }
            if best == nil || score < best!.score { best = (i, score) }
        }
        return best?.index
    }

    /// Switches the selected tower to its next target priority.
    @discardableResult
    func cycleSelectedPriority() -> TargetPriority? {
        guard let index = selectedIndex, placed.indices.contains(index) else { return nil }
        placed[index].priority = placed[index].priority.next
        return placed[index].priority
    }

    private var footprints: [TowerType: CGRect] = [:]

    /// The area that is actually drawn for this tower (its outline), measured from its
    /// picture, relative to the tower's position.
    func footprint(of type: TowerType) -> CGRect {
        if let cached = footprints[type] { return cached }
        let icon = type.makeIcon(enabled: true)
        var rect = CGRect.null
        for child in icon.children { rect = rect.union(child.calculateAccumulatedFrame()) }
        if rect.isNull || rect.width < 8 || rect.height < 8 {
            rect = CGRect(x: -12, y: -12, width: 24, height: 24)
        }
        footprints[type] = rect
        return rect
    }

    /// Builds the tower on the map. Returns false (and does nothing) if the
    /// spot is invalid. The caller handles payment.
    @discardableResult
    func place(_ type: TowerType, at point: CGPoint) -> Bool {
        guard isValidPlacement(at: point, type: type) else { return false }

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
        node.addChild(DebugOverlay.makeCircle(radius: min(type.spec.range, 600),
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
        tower.node.addChild(makeRangeRing(for: tower))
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
        pips.position = CGPoint(x: 0, y: 22 + 12)
        tower.node.addChild(pips)
    }

    /// The range ring, with dark wedges where an obstacle blocks the view
    /// (the tower can't shoot anything standing in a wedge).
    private func makeRangeRing(for tower: PlacedTower) -> SKShapeNode {
        let fullRange = tower.spec.range
        // A global-range tower has no circle; its blocked wedges are drawn out to about a screen's length.
        let range = min(fullRange, 1200)
        let ring: SKShapeNode
        if tower.spec.isGlobalRange {
            ring = SKShapeNode()
            ring.name = "rangeRing"
            ring.zPosition = -1
        } else {
            ring = TowerVisuals.makeRangeRing(radius: range)
        }
        guard tower.type != .ice, tower.type != .trapper else { return ring } // these ignore blocking
        for o in path.obstacles {
            let dx = o.center.x - tower.node.position.x
            let dy = o.center.y - tower.node.position.y
            let d = hypot(dx, dy)
            guard d > o.radius, d - o.radius < range else { continue }
            let centerAngle = atan2(dy, dx)
            let half = asin(min(1, o.radius / d))
            let near = sqrt(max(0, d * d - o.radius * o.radius))
            let a1 = centerAngle - half, a2 = centerAngle + half
            let wedge = CGMutablePath()
            wedge.move(to: CGPoint(x: cos(a1) * near, y: sin(a1) * near))
            wedge.addLine(to: CGPoint(x: cos(a1) * range, y: sin(a1) * range))
            wedge.addArc(center: .zero, radius: range, startAngle: a1, endAngle: a2, clockwise: false)
            wedge.addLine(to: CGPoint(x: cos(a2) * near, y: sin(a2) * near))
            wedge.closeSubpath()
            let shade = SKShapeNode(path: wedge)
            shade.fillColor = SKColor.black.withAlphaComponent(0.35)
            shade.strokeColor = .clear
            ring.addChild(shade)
        }
        return ring
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
        // The nearest tower under the finger (towers can now sit right next to each other).
        let hit = placed.indices
            .map { (index: $0, d: hypot(point.x - placed[$0].node.position.x, point.y - placed[$0].node.position.y)) }
            .filter { $0.d <= TowerManager.radius + 18 }
            .min { $0.d < $1.d }?.index
        guard hit != selectedIndex else { return false }
        deselect()
        if let hit {
            selectedIndex = hit
            // (No yellow selection circle: the range ring shows which tower is selected.)
            // Show how far this tower can shoot while it's selected.
            placed[hit].node.addChild(makeRangeRing(for: placed[hit]))
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
        zombies.prepareProgress()
        for tower in placed {
            let spec = tower.spec
            let key = ObjectIdentifier(tower.node)

            // Swing the gun around to face the nearest zombie in range.
            if tower.type.turnsToAim {
                if let index = pickTarget(for: tower, spec: spec, in: zombies.zombies) {
                    aim(tower, at: zombies.zombies[index].node.position)
                }
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
                        zombies.slow(at: i, duration: spec.slowDuration, factor: spec.slowFactor)
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
                SoundManager.shared.play(.frost)
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
                let first = pickTarget(for: tower, spec: spec, in: all).map { (index: $0, distance: CGFloat(0)) }
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
                SoundManager.shared.play(.tesla)
                for p in points {
                    DamageEffects.showImpact(spec.damageType, at: p, radius: 0, in: world)
                }
                // Highest index first so a kill never shifts a zombie we haven't hit yet.
                for i in chain.sorted(by: >) {
                    zombies.applyDamage(at: i, damage: spec.damage, type: spec.damageType)
                }
                continue
            }

            let nearest = pickTarget(for: tower, spec: spec, in: all).map { (index: $0, distance: CGFloat(0)) }
            guard let target = nearest else {
                fireTimers[key] = spec.fireInterval // ready; waits for a target
                continue
            }
            fireTimers[key] = 0
            if tower.type == .sniper {
                // The sniper never misses: the shot lands instantly on the target it picked.
                let origin = tower.node.position
                let hitPoint = all[target.index].node.position
                let angle = atan2(hitPoint.y - origin.y, hitPoint.x - origin.x)
                DamageEffects.showMuzzle(spec.damageType, at: origin, angle: angle, speed: spec.speed, in: world)
                DamageEffects.streak(from: origin, to: hitPoint, color: .white, width: 1.5, duration: 0.12, in: world)
                DamageEffects.showImpact(spec.damageType, at: hitPoint, radius: 0, in: world)
                zombies.applyDamage(at: target.index, damage: spec.damage, type: spec.damageType)
            } else {
                projectiles.fire(from: tower.node.position, at: all[target.index], spec: spec)
            }
            switch tower.type {
            case .flamethrower: SoundManager.shared.play(.flame)
            case .sniper, .grenadier: SoundManager.shared.play(.heavyShot)
            default: SoundManager.shared.play(.shot)
            }
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
        for points in path.lanes where points.count >= 2 {
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
