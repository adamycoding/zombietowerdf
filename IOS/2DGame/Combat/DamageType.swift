//
//  DamageType.swift
//  Combat
//
//  MH2D-95: the kinds of damage a tower can deal, how each kind of zombie
//  reacts to them (resistances), and the little visual effect each kind
//  plays where it lands (MH2D-96).
//

import SpriteKit
import UIKit

enum DamageType: CaseIterable {
    case bullet      // Soldier, Sniper: plain single-target hits
    case explosive   // Grenadier: area blast
    case frost       // Ice tower: slows instead of hurting
    case fire        // Flamethrower: short-range burning
    case electric    // Tesla: chain lightning that jumps between zombies
    case trap        // Barbed wire: hurts zombies that walk over it

    var displayName: String {
        switch self {
        case .bullet: return "Bullet"
        case .explosive: return "Explosive"
        case .frost: return "Frost"
        case .fire: return "Fire"
        case .electric: return "Electric"
        case .trap: return "Trap"
        }
    }

    /// Color of this damage type's impact effect.
    var effectColor: UIColor {
        switch self {
        case .bullet: return .systemYellow
        case .explosive: return .systemOrange
        case .frost: return .systemCyan
        case .fire: return UIColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 1)
        case .electric: return UIColor(red: 0.72, green: 0.62, blue: 1.0, alpha: 1)
        case .trap: return .lightGray
        }
    }
}

extension ZombieType {
    /// How much of a hit this kind of zombie takes: 1.0 = normal, 0.5 =
    /// resists (half damage), 1.5 = weak (50% extra). A normal zombie has
    /// no strengths or weaknesses. When enemy variety (MH2D-20) adds new
    /// zombie types, give each its own row here.
    func damageMultiplier(for type: DamageType) -> Double {
        switch self {
        case .normal:
            return 1.0
        case .runner:
            // Fragile: wire and fire catch it hard.
            return (type == .trap || type == .fire) ? 1.5 : 1.0
        case .brute:
            // Thick hide: bullets bounce off, blasts and electricity hurt.
            switch type {
            case .bullet: return 0.5
            case .fire: return 0.75
            case .trap: return 0.5
            case .explosive: return 1.5
            case .electric: return 1.25
            default: return 1.0
            }
        }
    }
}

enum DamageEffects {

    /// How many effect pieces are on screen right now. In the late waves
    /// (lots of zombies, lots of towers) effects are skipped once this gets
    /// high so the game never slows down; the gameplay itself is unaffected.
    private static var liveEffects = 0
    private static let maxLiveEffects = 250
    private static var hasRoom: Bool { liveEffects < maxLiveEffects }
    private static func effectStarted() { liveEffects += 1 }
    private static func effectEnded() { liveEffects = max(0, liveEffects - 1) }

    /// Called when a new game starts (a restarted scene never finishes the
    /// old scene's effects, so the count has to start over).
    static func reset() { liveEffects = 0 }

    // MARK: Building blocks (all cosmetic, all clean themselves up)

    /// A soft circle that grows (or shrinks), drifts, and fades out.
    static func puff(at position: CGPoint, radius: CGFloat, color: UIColor,
                     startScale: CGFloat = 0.3, endScale: CGFloat = 1,
                     duration: TimeInterval, drift: CGVector = .zero,
                     stroke: UIColor = .clear, in world: SKNode) {
        guard hasRoom else { return }
        effectStarted()
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = position
        node.fillColor = stroke == .clear ? color : .clear
        node.strokeColor = stroke
        node.lineWidth = stroke == .clear ? 0 : 3
        node.zPosition = Layer.projectiles.rawValue
        node.setScale(startScale)
        world.addChild(node)
        node.run(.sequence([
            .group([
                .scale(to: endScale, duration: duration),
                .fadeOut(withDuration: duration),
                .moveBy(x: drift.dx, y: drift.dy, duration: duration)
            ]),
            .run { effectEnded() },
            .removeFromParent()
        ]))
    }

    /// A short straight streak that fades out.
    static func streak(from a: CGPoint, to b: CGPoint, color: UIColor,
                       width: CGFloat = 2, duration: TimeInterval, in world: SKNode) {
        guard hasRoom else { return }
        effectStarted()
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.lineWidth = width
        node.lineCap = .round
        node.zPosition = Layer.projectiles.rawValue
        world.addChild(node)
        node.run(.sequence([.fadeOut(withDuration: duration), .run { effectEnded() }, .removeFromParent()]))
    }

    /// Spokes shooting out from a point (sparks, snow crystals, crackle).
    private static func spokes(at p: CGPoint, count: Int, inner: CGFloat, outer: CGFloat,
                               color: UIColor, width: CGFloat, duration: TimeInterval,
                               jitter: Bool = false, in world: SKNode) {
        for k in 0..<count {
            var angle = CGFloat(k) / CGFloat(count) * 2 * .pi
            if jitter { angle += CGFloat.random(in: -0.4...0.4) }
            let reach = jitter ? outer * CGFloat.random(in: 0.6...1.0) : outer
            streak(from: CGPoint(x: p.x + cos(angle) * inner, y: p.y + sin(angle) * inner),
                   to: CGPoint(x: p.x + cos(angle) * reach, y: p.y + sin(angle) * reach),
                   color: color, width: width, duration: duration, in: world)
        }
    }

    // MARK: Firing (muzzle) effects

    /// MH2D-96: what you see at the barrel when a tower shoots.
    static func showMuzzle(_ type: DamageType, at origin: CGPoint, angle: CGFloat,
                           speed: CGFloat, in world: SKNode) {
        let dir = CGVector(dx: cos(angle), dy: sin(angle))
        let tip = CGPoint(x: origin.x + dir.dx * 14, y: origin.y + dir.dy * 14)
        switch type {
        case .bullet:
            if speed >= 600 { // sniper: big white flash and a long crack
                puff(at: tip, radius: 7, color: .white, startScale: 0.5, endScale: 1.4, duration: 0.1, in: world)
                streak(from: tip, to: CGPoint(x: tip.x + dir.dx * 14, y: tip.y + dir.dy * 14),
                       color: .white, width: 2, duration: 0.1, in: world)
            } else {
                puff(at: tip, radius: 4, color: .systemYellow, startScale: 0.5, endScale: 1.3, duration: 0.07, in: world)
            }
        case .explosive: // grenade launcher: puff of smoke
            puff(at: tip, radius: 6, color: UIColor(white: 0.8, alpha: 0.8), startScale: 0.4, endScale: 1.8,
                 duration: 0.4, drift: CGVector(dx: 0, dy: 6), in: world)
        case .fire: // flame nozzle glow
            puff(at: tip, radius: 6, color: .systemYellow, startScale: 0.5, endScale: 1.2, duration: 0.1, in: world)
        default:
            break
        }
    }

    /// Flamethrower: a stream of licking flames out of the nozzle. Purely
    /// cosmetic, the real damage comes from the flame shot itself.
    static func showFlameStream(from origin: CGPoint, angle: CGFloat, reach: CGFloat, in world: SKNode) {
        let dir = CGVector(dx: cos(angle), dy: sin(angle))
        let side = CGVector(dx: -dir.dy, dy: dir.dx)
        let colors: [UIColor] = [
            UIColor(red: 1.0, green: 0.25, blue: 0.05, alpha: 1),
            UIColor(red: 1.0, green: 0.50, blue: 0.10, alpha: 1),
            UIColor(red: 1.0, green: 0.80, blue: 0.20, alpha: 1)
        ]
        for k in 0..<9 {
            guard hasRoom else { return }
            effectStarted()
            let blob = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...5))
            blob.fillColor = colors[k % colors.count].withAlphaComponent(0.9)
            blob.strokeColor = .clear
            blob.position = CGPoint(x: origin.x + dir.dx * 12, y: origin.y + dir.dy * 12)
            blob.zPosition = Layer.projectiles.rawValue
            world.addChild(blob)
            let travel = reach * CGFloat.random(in: 0.5...1.0)
            let wobble = CGFloat.random(in: -9...9)
            let duration = TimeInterval.random(in: 0.22...0.36)
            blob.run(.sequence([
                .group([
                    .moveBy(x: dir.dx * travel + side.dx * wobble,
                            y: dir.dy * travel + side.dy * wobble + 4, duration: duration),
                    .scale(to: 2.4, duration: duration),
                    .fadeOut(withDuration: duration)
                ]),
                .run { effectEnded() },
                .removeFromParent()
            ]))
        }
    }

    // MARK: Impact effects

    /// MH2D-96: what happens where a hit lands. `radius` is the blast size
    /// for explosive hits (ignored for the others).
    static func showImpact(_ type: DamageType, at p: CGPoint, radius: CGFloat, in world: SKNode) {
        switch type {
        case .bullet:
            puff(at: p, radius: 4, color: .white, startScale: 0.5, endScale: 1.8, duration: 0.1, in: world)
            spokes(at: p, count: 4, inner: 3, outer: 10, color: .systemYellow, width: 1.5,
                   duration: 0.12, jitter: true, in: world)

        case .explosive:
            let r = max(radius, 20)
            // Fireball, hot core, shockwave, lingering smoke, flying sparks.
            puff(at: p, radius: r * 0.8, color: UIColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 0.9),
                 startScale: 0.3, endScale: 1.0, duration: 0.25, in: world)
            puff(at: p, radius: r * 0.45, color: .systemYellow, startScale: 0.3, endScale: 1.0,
                 duration: 0.2, in: world)
            puff(at: p, radius: r, color: .clear, startScale: 0.3, endScale: 1.0, duration: 0.3,
                 stroke: UIColor.white.withAlphaComponent(0.8), in: world)
            puff(at: p, radius: r * 0.6, color: UIColor(white: 0.25, alpha: 0.55), startScale: 0.5,
                 endScale: 1.5, duration: 0.7, drift: CGVector(dx: 0, dy: 10), in: world)
            spokes(at: p, count: 8, inner: r * 0.5, outer: r * 1.1, color: .systemYellow, width: 2,
                   duration: 0.25, jitter: true, in: world)

        case .frost:
            // Ice burst: a frosty ring, six crystal spokes, a mist of snow.
            puff(at: p, radius: max(radius, 14), color: UIColor.systemCyan.withAlphaComponent(0.35),
                 startScale: 0.3, endScale: 1.0, duration: 0.35, in: world)
            spokes(at: p, count: 6, inner: 3, outer: max(radius, 14), color: .white, width: 1.5,
                   duration: 0.35, in: world)

        case .fire:
            // Little flames that lick upward off the burning zombie.
            for k in 0..<4 {
                let colors: [UIColor] = [.systemRed, UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 1), .systemYellow]
                puff(at: CGPoint(x: p.x + CGFloat.random(in: -6...6), y: p.y + CGFloat.random(in: -3...3)),
                     radius: CGFloat.random(in: 3...5), color: colors[k % colors.count],
                     startScale: 0.5, endScale: 1.4, duration: 0.4,
                     drift: CGVector(dx: CGFloat.random(in: -3...3), dy: 14), in: world)
            }

        case .electric:
            // Crackle: bright flash and jagged sparks.
            puff(at: p, radius: 6, color: .white, startScale: 0.4, endScale: 1.5, duration: 0.15, in: world)
            spokes(at: p, count: 6, inner: 2, outer: 14, color: type.effectColor, width: 1.5,
                   duration: 0.15, jitter: true, in: world)

        case .trap:
            // Metal sparks off the wire.
            puff(at: p, radius: 4, color: UIColor(white: 0.9, alpha: 1), startScale: 0.5, endScale: 1.6,
                 duration: 0.12, in: world)
            spokes(at: p, count: 5, inner: 2, outer: 11, color: .lightGray, width: 1.5,
                   duration: 0.15, jitter: true, in: world)
        }
    }
}
