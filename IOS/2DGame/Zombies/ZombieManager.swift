//
//  ZombieManager.swift
//  Zombies
//
//  Owns every zombie: spawning, walking the route, slow effects, health
//  and damage. Other systems (towers, projectiles) talk to zombies only
//  through this class.
//

import SpriteKit
import UIKit

final class ZombieManager {

    struct Zombie {
        let node: SKShapeNode
        var nextWaypointIndex: Int = 1
        var hurtbox = Hurtbox(radius: ZombieManager.radius) // MH2D-45
        var slowTimer: TimeInterval = 0 // > 0 while slowed by an ice tower
        var maxHealth: Int = ZombieManager.normalHealth // MH2D-52
        var health: Int = ZombieManager.normalHealth
        var reward: Int = ZombieManager.normalReward    // MH2D-53
    }

    /// Drawn radius of a zombie; its hurtbox uses the same number so the
    /// box always lines up with what you see.
    static let radius: CGFloat = 12
    /// MH2D-52: hit points of a normal zombie. Enemy types (MH2D-20) will
    /// each set their own number.
    static let normalHealth = 3
    static let healthBarWidth: CGFloat = 24
    /// MH2D-53: money paid to the player when a normal zombie is killed.
    /// Enemy types (MH2D-20) will each set their own number.
    static let normalReward = 10

    static let iceSlowFactor: CGFloat = 0.45   // 45% speed while slowed
    static let iceSlowDuration: TimeInterval = 2.0

    let speed: CGFloat = 60
    let normalSpawnInterval: TimeInterval = 1.5
    /// Stress test shortens this.
    var spawnInterval: TimeInterval = 1.5

    private(set) var zombies: [Zombie] = []

    /// MH2D-53: called with the reward when a zombie is killed by damage.
    /// Zombies that reach the end of the path do NOT trigger this.
    var onZombieKilled: ((Int) -> Void)?
    var onWaveCompleted: ((Int) -> Void)?
    
    
    private let world: SKNode
    private let path: GamePath
    private var spawnTimer: TimeInterval = 0
    private let waves: [WaveDefinition] = [
        WaveDefinition(
            zombieTypes: Array(repeating: .normal, count: 5),
            spawnInterval: 1.5
        ),
        WaveDefinition(
            zombieTypes: Array(repeating: .normal, count: 8),
            spawnInterval: 1.2
        ),
        WaveDefinition(
            zombieTypes: Array(repeating: .normal, count: 10),
            spawnInterval: 1.0
        ),
        WaveDefinition(
            zombieTypes: Array(repeating: .normal, count: 12),
            spawnInterval: 0.9
        ),
        WaveDefinition(
            zombieTypes: Array(repeating: .normal, count: 15),
            spawnInterval: 0.8
        )
    ]

    private var waveDefinition: WaveDefinition {
        waves[currentWave - 1]
    }

    private var zombiesPerWave: Int {
        waveDefinition.zombieCount
    }
    
    //tracks how many have spawned so far.
    private var zombiesSpawnedThisWave: Int = 0

    init(world: SKNode, path: GamePath) {
        self.world = world
        self.path = path
    }

    // MARK: Spawning

    /// Don't bank spawn time while there's no route yet.
    func resetSpawnTimer() {
        spawnTimer = 0
    }

    func updateSpawning(deltaTime: TimeInterval) {
        guard zombiesSpawnedThisWave < zombiesPerWave else {
            return
        }

        spawnTimer += deltaTime

        while spawnTimer >= waveDefinition.spawnInterval &&              zombiesSpawnedThisWave < zombiesPerWave {
            spawnTimer -= waveDefinition.spawnInterval
            let type = waveDefinition.zombieTypes[zombiesSpawnedThisWave]
            spawn(type: type)
            zombiesSpawnedThisWave += 1
        }
    }
    
    private func spawn(type: ZombieType) {        guard let startPoint = path.waypoints.first else { return }

        let zombie = SKShapeNode(circleOfRadius: ZombieManager.radius)
        zombie.name = "zombie"
        switch type {
        case .normal:
            zombie.fillColor = .systemGreen
        }
        zombie.strokeColor = .black
        zombie.lineWidth = 2
        zombie.position = startPoint
        zombie.zPosition = Layer.zombies.rawValue
        // MH2D-12: outline of the hurtbox (only visible when the overlay is on)
        zombie.addChild(DebugOverlay.makeCircle(radius: ZombieManager.radius, color: .yellow, name: "hurtboxDebug"))

        // MH2D-52: small health bar above the zombie (red = missing health).
        let width = ZombieManager.healthBarWidth
        let barBack = SKSpriteNode(color: .systemRed, size: CGSize(width: width, height: 3))
        barBack.name = "healthBack"
        barBack.position = CGPoint(x: 0, y: ZombieManager.radius + 6)
        barBack.zPosition = 4
        let barFill = SKSpriteNode(color: .systemGreen, size: CGSize(width: width, height: 3))
        barFill.name = "healthFill"
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        barFill.position = CGPoint(x: -width / 2, y: 0)
        barBack.addChild(barFill)
        barBack.isHidden = true // shown once the zombie has taken damage
        zombie.addChild(barBack)

        world.addChild(zombie)
        zombies.append(Zombie(node: zombie))
    }

    // MARK: Movement

    func move(deltaTime: TimeInterval) {
        let waypoints = path.waypoints
        // Work backward so removing a zombie doesn't shift
        // the indexes of zombies we still need to update.
        for index in zombies.indices.reversed() {
            let zombie = zombies[index].node
            // Ice tower slow: zombies crawl at iceSlowFactor of normal speed.
            var speedMultiplier: CGFloat = 1
            if zombies[index].slowTimer > 0 {
                zombies[index].slowTimer -= deltaTime
                speedMultiplier = ZombieManager.iceSlowFactor
                zombie.fillColor = .systemTeal
            } else {
                zombie.fillColor = .systemGreen
            }
            var remainingMovement = speed * speedMultiplier * CGFloat(deltaTime)

            while remainingMovement > 0 {
                let waypointIndex = zombies[index].nextWaypointIndex

                guard waypointIndex < waypoints.count else {
                    zombie.removeFromParent()
                    zombies.remove(at: index)
                    break
                }

                let target = waypoints[waypointIndex]
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

    /// Zombies store an index into the waypoints, so if the route moves they
    /// would snap to the new coordinates. Keep each zombie the same fraction
    /// of the way along its current segment on the new route.
    /// Call with the route as it was *before* the change (`oldWaypoints`).
    func remapProgress(from oldWaypoints: [CGPoint]) {
        let newWaypoints = path.waypoints
        for index in zombies.indices {
            let next = zombies[index].nextWaypointIndex
            guard next >= 1, next < oldWaypoints.count, next < newWaypoints.count else { continue }
            let from = oldWaypoints[next - 1]
            let to = oldWaypoints[next]
            let length = hypot(to.x - from.x, to.y - from.y)
            guard length > 0 else { continue }
            let travelled = hypot(zombies[index].node.position.x - from.x,
                                  zombies[index].node.position.y - from.y)
            let t = min(1, travelled / length)
            let newFrom = newWaypoints[next - 1]
            let newTo = newWaypoints[next]
            zombies[index].node.position = CGPoint(
                x: newFrom.x + (newTo.x - newFrom.x) * t,
                y: newFrom.y + (newTo.y - newFrom.y) * t
            )
        }
    }

    // MARK: Effects on zombies

    func slow(at index: Int, duration: TimeInterval) {
        guard zombies.indices.contains(index) else { return }
        zombies[index].slowTimer = duration
    }

    /// MH2D-52: apply a projectile's damage to the zombie it hit. Health drops
    /// by exactly `damage`; the health bar and a short white flash show it.
    /// A killed zombie is removed and pays its reward (MH2D-53); the death
    /// effect is MH2D-54.
    func applyDamage(at index: Int, damage: Int) {
        guard zombies.indices.contains(index) else { return }
        zombies[index].health = max(0, zombies[index].health - damage)
        let state = zombies[index]
        updateHealthBar(of: state)
        flashHit(state.node)

        if state.health <= 0 {
            die(at: index)
        }
    }

    /// MH2D-53: remove the zombie and pay its reward.
    /// MH2D-54: play the death effect (red pop, burst of bits, floating "+$").
    private func die(at index: Int) {
        let node = zombies[index].node
        let reward = zombies[index].reward
        zombies.remove(at: index)
        onZombieKilled?(reward)
        playDeathEffect(on: node, reward: reward)
    }

    /// MH2D-54: everything here is cosmetic and cleans itself up.
    private func playDeathEffect(on node: SKShapeNode, reward: Int) {
        node.removeAllActions()
        node.childNode(withName: "healthBack")?.isHidden = true
        node.fillColor = .systemRed
        node.run(.sequence([
            .group([.fadeOut(withDuration: 0.2), .scale(to: 1.5, duration: 0.2)]),
            .removeFromParent()
        ]))

        guard let parent = node.parent else { return }
        let origin = node.position

        // Burst of small red bits flying outward.
        let bitCount = 6
        for i in 0..<bitCount {
            let bit = SKShapeNode(circleOfRadius: 2.5)
            bit.fillColor = .systemRed
            bit.strokeColor = .clear
            bit.position = origin
            bit.zPosition = Layer.effects.rawValue
            parent.addChild(bit)
            let angle = CGFloat(i) / CGFloat(bitCount) * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let distance = CGFloat.random(in: 16...26)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.3)
            move.timingMode = .easeOut
            bit.run(.sequence([.group([move, .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        }

        // Floating "+$10" so the reward is visible.
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "+$\(reward)"
        label.fontSize = 12
        label.fontColor = .systemYellow
        label.position = CGPoint(x: origin.x, y: origin.y + 14)
        label.zPosition = Layer.effects.rawValue
        parent.addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 18, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent()
        ]))
    }

    /// Resize the green part of the bar to health / maxHealth and show it.
    private func updateHealthBar(of zombie: Zombie) {
        guard let back = zombie.node.childNode(withName: "healthBack") as? SKSpriteNode,
              let fill = back.childNode(withName: "healthFill") as? SKSpriteNode else { return }
        back.isHidden = false
        let fraction = CGFloat(zombie.health) / CGFloat(max(1, zombie.maxHealth))
        fill.size.width = ZombieManager.healthBarWidth * fraction
    }

    /// Brief white flash so each hit is visible.
    private func flashHit(_ node: SKShapeNode) {
        node.removeAction(forKey: "hitFlash")
        node.run(.sequence([
            .run { node.strokeColor = .white },
            .wait(forDuration: 0.08),
            .run { node.strokeColor = .black }
        ]), withKey: "hitFlash")
    }
    
    // Checks if wave has fully spawned and if there is no zombies left.
    var isWaveComplete: Bool {
        zombiesSpawnedThisWave >= zombiesPerWave &&
        zombies.isEmpty
    }
    
    private(set) var currentWave: Int = 1
    
    var totalWaves: Int {
        waves.count
    }
    
    private var hasAnnouncedWaveCompletion: Bool = false
    
    func checkWaveCompletion() {
        guard isWaveComplete && !hasAnnouncedWaveCompletion else {
            return
        }

        hasAnnouncedWaveCompletion = true
        print("Wave \(currentWave) Complete")
        onWaveCompleted?(currentWave)

        guard currentWave < waves.count else {
            print("All waves complete!")
            return
        }

        currentWave += 1
        zombiesSpawnedThisWave = 0
        spawnTimer = 0
        hasAnnouncedWaveCompletion = false

        print("Starting Wave \(currentWave)")
    }
    
    
}
