//
//  ProjectileSystem.swift
//  Combat
//
//  MH2D-46: creates projectiles, moves them each tick, and checks them
//  against zombie hurtboxes with a swept circle test so a fast shot can
//  never skip over a zombie between two ticks.
//

import SpriteKit
import UIKit

final class ProjectileSystem {

    private struct Projectile {
        let node: SKShapeNode
        var velocity: CGVector
        let hitbox: Hitbox
        var age: TimeInterval = 0
        let lifetime: TimeInterval
        let damage: Int
        let damageType: DamageType
        let blastRadius: CGFloat
    }

    private var projectiles: [Projectile] = []
    private(set) var hitCount = 0
    private(set) var missCount = 0
    var activeCount: Int { projectiles.count }

    private let world: SKNode
    private let zombies: ZombieManager
    private let path: GamePath

    init(world: SKNode, zombies: ZombieManager, path: GamePath) {
        self.world = world
        self.zombies = zombies
        self.path = path
    }

    /// What a projectile looks like depends on what it does: bullets are
    /// bright tracers, grenades are fat shells, flames are glowing blobs.
    private func makeNode(_ spec: ProjectileSpec, angle: CGFloat) -> SKShapeNode {
        let node: SKShapeNode
        switch spec.damageType {
        case .bullet:
            let length = max(8, spec.speed * 0.03)
            let streak = CGMutablePath()
            streak.move(to: CGPoint(x: -length, y: 0))
            streak.addLine(to: .zero)
            node = SKShapeNode(path: streak)
            node.strokeColor = spec.color
            node.lineWidth = max(2, spec.radius * 0.8)
            node.lineCap = .round
            node.zRotation = angle
            let tip = SKShapeNode(circleOfRadius: max(1.5, spec.radius * 0.7))
            tip.fillColor = .white
            tip.strokeColor = .clear
            node.addChild(tip)
        case .explosive:
            node = SKShapeNode(circleOfRadius: spec.radius)
            node.fillColor = UIColor(red: 0.28, green: 0.32, blue: 0.2, alpha: 1)
            node.strokeColor = .systemOrange
            node.lineWidth = 2
            let fuse = SKShapeNode(circleOfRadius: 2)
            fuse.fillColor = .systemYellow
            fuse.strokeColor = .clear
            fuse.position = CGPoint(x: -spec.radius * 0.6, y: spec.radius * 0.6)
            node.addChild(fuse)
        case .fire:
            node = SKShapeNode(circleOfRadius: spec.radius)
            node.fillColor = spec.color.withAlphaComponent(0.9)
            node.strokeColor = .clear
            node.run(.group([.scale(to: 2.0, duration: spec.lifetime),
                             .fadeAlpha(to: 0.4, duration: spec.lifetime)]))
        default:
            node = SKShapeNode(circleOfRadius: spec.radius)
            node.fillColor = spec.color
            node.strokeColor = .clear
        }
        node.zPosition = Layer.projectiles.rawValue
        return node
    }

    func fire(from origin: CGPoint, at zombie: ZombieManager.Zombie, spec: ProjectileSpec) {
        // Aim where the zombie will be when the shot arrives (first-order lead).
        let lanes = path.lanes
        let waypoints = lanes.isEmpty ? [] : lanes[min(zombie.lane, lanes.count - 1)]
        let pos = zombie.node.position
        var aim = pos
        if zombie.nextWaypointIndex < waypoints.count {
            let next = waypoints[zombie.nextWaypointIndex]
            let dx = next.x - pos.x
            let dy = next.y - pos.y
            let length = hypot(dx, dy)
            if length > 0 {
                let flightTime = hypot(pos.x - origin.x, pos.y - origin.y) / spec.speed
                let slow = zombie.slowTimer > 0 ? zombie.slowFactor : 1
                let targetSpeed = zombies.speed * zombie.type.speedFactor * slow
                let reach = min(length, targetSpeed * flightTime)
                aim = CGPoint(x: pos.x + dx / length * reach, y: pos.y + dy / length * reach)
            }
        }
        let ax = aim.x - origin.x
        let ay = aim.y - origin.y
        let aimLength = hypot(ax, ay)
        guard aimLength > 0 else { return }

        let angle = atan2(ay, ax)
        let node = makeNode(spec, angle: angle)
        node.position = origin
        // Hitbox outline only while the debug overlay is on (a hidden shape per shot still costs time).
        if DebugOverlay.showHitboxes {
            node.addChild(DebugOverlay.makeCircle(radius: spec.radius, color: .red, name: "hitboxDebug"))
        }
        world.addChild(node)

        // Effects that make each shot read as what it is.
        DamageEffects.showMuzzle(spec.damageType, at: origin, angle: angle, speed: spec.speed, in: world)
        switch spec.damageType {
        case .explosive:
            // Lobbed shell: rises and falls, trailing smoke.
            let flight = TimeInterval(aimLength / spec.speed)
            node.run(.sequence([.scale(to: 1.7, duration: flight / 2), .scale(to: 1.0, duration: flight / 2)]))
            node.run(.repeatForever(.sequence([
                .wait(forDuration: 0.05),
                .run { [weak node, weak self] in
                    guard let node, let self else { return }
                    DamageEffects.puff(at: node.position, radius: 3,
                                       color: UIColor(white: 0.75, alpha: 0.7), startScale: 0.6,
                                       endScale: 1.6, duration: 0.35, in: self.world)
                }
            ])))
        case .fire:
            DamageEffects.showFlameStream(from: origin, angle: angle, reach: spec.range, in: world)
        default:
            break
        }

        projectiles.append(Projectile(
            node: node,
            velocity: CGVector(dx: ax / aimLength * spec.speed, dy: ay / aimLength * spec.speed),
            hitbox: Hitbox(radius: spec.radius),
            lifetime: spec.lifetime,
            damage: spec.damage,
            damageType: spec.damageType,
            blastRadius: spec.blastRadius
        ))
    }

    /// Move every projectile and check it against every hurtbox.
    /// `bounds` is the scene size; shots that leave it are discarded.
    func update(deltaTime: TimeInterval, bounds: CGSize) {
        for index in projectiles.indices.reversed() {
            var shot = projectiles[index]
            let from = shot.node.position
            let to = CGPoint(x: from.x + shot.velocity.dx * CGFloat(deltaTime),
                             y: from.y + shot.velocity.dy * CGFloat(deltaTime))
            shot.age += deltaTime

            // Swept check against all zombies; keep the earliest contact.
            var hitIndex: Int?
            var earliest = CGFloat.greatestFiniteMagnitude
            for (zi, zombie) in zombies.zombies.enumerated() {
                let reach = shot.hitbox.radius + zombie.hurtbox.radius
                if let t = ProjectileSystem.sweptCircleHit(from: from, to: to,
                                                           center: zombie.node.position, radius: reach),
                   t < earliest {
                    earliest = t
                    hitIndex = zi
                }
            }

            if let zi = hitIndex {
                hitCount += 1
                let impact = CGPoint(x: from.x + (to.x - from.x) * earliest,
                                     y: from.y + (to.y - from.y) * earliest)
                if shot.blastRadius > 0 {
                    // MH2D-76: area damage. Everything inside the blast takes the hit.
                    // Highest index first so a kill (which removes that zombie)
                    // never shifts a zombie we haven't hit yet.
                    for i in zombies.zombies.indices.reversed() {
                        let z = zombies.zombies[i]
                        let d = hypot(z.node.position.x - impact.x, z.node.position.y - impact.y)
                        if d <= shot.blastRadius + z.hurtbox.radius {
                            zombies.applyDamage(at: i, damage: shot.damage, type: shot.damageType)
                        }
                    }
                } else {
                    zombies.applyDamage(at: zi, damage: shot.damage, type: shot.damageType)
                }
                DamageEffects.showImpact(shot.damageType, at: impact, radius: shot.blastRadius, in: world)
                shot.node.removeFromParent()
                projectiles.remove(at: index)
                continue
            }

            shot.node.position = to
            let outside = to.x < 0 || to.y < 0 || to.x > bounds.width || to.y > bounds.height
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
    static func sweptCircleHit(from a: CGPoint, to b: CGPoint, center c: CGPoint, radius r: CGFloat) -> CGFloat? {
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
}
