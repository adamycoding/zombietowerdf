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

    /// Swap this to change what a projectile looks like (sprite, trail, ...).
    private func makeNode(_ spec: ProjectileSpec) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: spec.radius)
        node.fillColor = spec.color
        node.strokeColor = .clear
        node.zPosition = Layer.projectiles.rawValue
        return node
    }

    func fire(from origin: CGPoint, at zombie: ZombieManager.Zombie, spec: ProjectileSpec) {
        // Aim where the zombie will be when the shot arrives (first-order lead).
        let waypoints = path.waypoints
        let pos = zombie.node.position
        var aim = pos
        if zombie.nextWaypointIndex < waypoints.count {
            let next = waypoints[zombie.nextWaypointIndex]
            let dx = next.x - pos.x
            let dy = next.y - pos.y
            let length = hypot(dx, dy)
            if length > 0 {
                let flightTime = hypot(pos.x - origin.x, pos.y - origin.y) / spec.speed
                let reach = min(length, zombies.speed * flightTime)
                aim = CGPoint(x: pos.x + dx / length * reach, y: pos.y + dy / length * reach)
            }
        }
        let ax = aim.x - origin.x
        let ay = aim.y - origin.y
        let aimLength = hypot(ax, ay)
        guard aimLength > 0 else { return }

        let node = makeNode(spec)
        node.position = origin
        node.addChild(DebugOverlay.makeCircle(radius: spec.radius, color: .red, name: "hitboxDebug"))
        world.addChild(node)
        projectiles.append(Projectile(
            node: node,
            velocity: CGVector(dx: ax / aimLength * spec.speed, dy: ay / aimLength * spec.speed),
            hitbox: Hitbox(radius: spec.radius),
            lifetime: spec.lifetime,
            damage: spec.damage
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
                zombies.applyDamage(at: zi, damage: shot.damage)
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
