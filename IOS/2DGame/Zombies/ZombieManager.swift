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
        let node: SKSpriteNode // one baked sprite per zombie (cheap to draw)
        var type: ZombieType = .normal // MH2D-95: decides resistances
        var nextWaypointIndex: Int = 1
        var lane: Int = 0 // which of the map's roads this zombie walks
        var hurtbox = Hurtbox(radius: ZombieManager.radius) // MH2D-45
        var slowTimer: TimeInterval = 0 // > 0 while slowed by an ice tower
        var slowFactor: CGFloat = 1     // speed share while slowed (set by the ice tower)
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
    static let normalReward = 5

    static let iceSlowFactor: CGFloat = 0.45   // 45% speed while slowed
    static let iceSlowDuration: TimeInterval = 2.0

    let speed: CGFloat = 60

    private(set) var zombies: [Zombie] = []

    /// MH2D-53: called with the reward when a zombie is killed by damage.
    /// Zombies that reach the end of the path do NOT trigger this.
    var onZombieKilled: ((Int) -> Void)?
    /// MH2D-55: called once for each zombie that walks off the end of the
    /// path. MH2D-56 uses this to take away base health.
    var onZombieReachedBase: (() -> Void)?
    /// MH2D-55: how many zombies have reached the base (debug / testing).
    private(set) var breachCount = 0
    var onWaveCompleted: ((Int) -> Void)?
    /// Called once when the last wave has been cleared.
    var onAllWavesCompleted: (() -> Void)?
    
    
    private let world: SKNode
    private let path: GamePath
    private var spawnTimer: TimeInterval = 0
    /// Total number of waves in a game.
    static let totalWaveCount = 40

    /// After the player chooses Continue on the win screen, waves keep coming past the last one.
    private(set) var isEndless = false

    /// Wave 1 has 10 zombies and every wave after it adds 4 more (wave 40 has
    /// 166). They also spawn faster as the waves go on, down to one every
    /// 0.25 s, so the difficulty keeps climbing the whole way.
    private static func makeWave(number: Int, multiplier: Double = 1) -> WaveDefinition {
        let count = Int((Double(10 + (number - 1) * 4) * multiplier).rounded())
        let interval = max(0.25, 1.2 - Double(number - 1) * 0.025)
        return WaveDefinition(zombieTypes: Array(repeating: .normal, count: count),
                              spawnInterval: interval)
    }

    private var waveDefinition: WaveDefinition {
        ZombieManager.makeWave(number: currentWave)
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
    
    /// Drawing a zombie from ~15 little shapes is slow (every shape is its own
    /// draw call), and a late wave has well over a hundred of them. So the
    /// zombie is drawn from shapes ONCE, turned into a texture, and every
    /// zombie is then a single sprite using that texture.
    private static var bakedBody: (frames: [SKTexture], size: CGSize, anchor: CGPoint)?

    /// Bakes the walk cycle: the same zombie in a few leg/arm positions. All
    /// frames are cut from the same rectangle, so the sprite never jumps.
    private static func bakeBody(using draw: (CGFloat) -> SKShapeNode) -> (frames: [SKTexture], size: CGSize, anchor: CGPoint) {
        if let baked = bakedBody { return baked }
        func prepare(_ phase: CGFloat) -> SKShapeNode {
            let shapes = draw(phase)
            shapes.fillColor = .systemGreen
            shapes.strokeColor = .black
            shapes.lineWidth = 2
            return shapes
        }
        let neutral = prepare(0)
        let frame = neutral.calculateAccumulatedFrame().insetBy(dx: -2, dy: -4)
        let view = SKView()
        // left foot forward, passing, right foot forward, passing
        let frames = ([1, 0, -1, 0] as [CGFloat]).map { phase -> SKTexture in
            view.texture(from: prepare(phase), crop: frame) ?? SKTexture()
        }
        let anchor = CGPoint(x: -frame.minX / frame.width, y: -frame.minY / frame.height)
        let baked = (frames: frames, size: frame.size, anchor: anchor)
        bakedBody = baked
        return baked
    }

    /// `phase` (-1...1) is where the legs and arms are in the walk cycle.
    private func makeZombieNode(phase: CGFloat = 0) -> SKShapeNode {
        // The main shape is now the head.
        // Existing damage and ice effects still change its color.
        let headPath = CGPath(
            ellipseIn: CGRect(x: -7, y: 1, width: 14, height: 14),
            transform: nil
        )
        let zombie = SKShapeNode(path: headPath)

        // Add a body part to the zombie.
        func addPart(
            width: CGFloat,
            height: CGFloat,
            x: CGFloat,
            y: CGFloat,
            color: SKColor
        ) -> SKShapeNode {
            let part = SKShapeNode(
                rectOf: CGSize(width: width, height: height),
                cornerRadius: 2
            )
            part.position = CGPoint(x: x, y: y)
            part.fillColor = color
            part.strokeColor = SKColor(white: 0.15, alpha: 1)
            part.lineWidth = 1
            part.zPosition = 1
            zombie.addChild(part)
            return part
        }

        // Shadow beneath the feet.
        let shadow = SKShapeNode(
            ellipseOf: CGSize(width: 20, height: 6)
        )
        shadow.position = CGPoint(x: 0, y: -12)
        shadow.fillColor = SKColor.black.withAlphaComponent(0.2)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        zombie.addChild(shadow)

        // Two walking legs.
        for side: CGFloat in [-1, 1] {
            let leg = addPart(
                width: 5, height: 9,
                x: side * 4, y: -8 + side * phase * 2.5,
                color: .darkGray
            )
            _ = leg
        }

        // Brown shirt.
        _ = addPart(
            width: 12, height: 10,
            x: 0, y: -1,
            color: SKColor(
                red: 0.39, green: 0.36, blue: 0.27, alpha: 1
            )
        )

        // Outstretched arms.
        for side: CGFloat in [-1, 1] {
            let arm = addPart(
                width: 4, height: 9,
                x: side * 8, y: -side * phase * 1.5,
                color: SKColor(
                    red: 0.57, green: 0.70, blue: 0.37, alpha: 1
                )
            )
            arm.zRotation = side * 0.4
        }

        // Eyes and pupils.
        for x: CGFloat in [-3, 3] {
            _ = addPart(
                width: 4, height: 4,
                x: x, y: 10,
                color: .white
            )
            let pupil = addPart(
                width: 1.5, height: 2,
                x: x, y: 10,
                color: .black
            )
            pupil.zPosition = 2
        }

        // Mouth.
        _ = addPart(
            width: 5, height: 2,
            x: 0, y: 5,
            color: .darkGray
        )

        return zombie
    }

    private func spawn(type: ZombieType) {
        guard !path.lanes.isEmpty else { return }
        // The wave's zombies are split across the roads in a fixed pattern
        // (zombie 1 -> road 1, zombie 2 -> road 2, ...), so a wave is the same
        // size on every map and always divides the same way.
        let lane = zombiesSpawnedThisWave % path.lanes.count
        guard let startPoint = path.lanes[lane].first else { return }

        let body = ZombieManager.bakeBody { makeZombieNode(phase: $0) }
        let zombie = SKSpriteNode(texture: body.frames[1], size: body.size)
        zombie.anchorPoint = body.anchor
        zombie.color = .systemTeal       // used as the tint while slowed / hit / dying
        zombie.colorBlendFactor = 0
        zombie.name = "zombie"
        zombie.position = startPoint
        zombie.zPosition = Layer.zombies.rawValue
        // MH2D-12: outline of the hurtbox. Only built while the overlay is on,
        // so normal play doesn't pay for a hidden node on every zombie.
        if DebugOverlay.showHitboxes {
            zombie.addChild(DebugOverlay.makeCircle(radius: ZombieManager.radius, color: .yellow, name: "hurtboxDebug"))
        }
        // (The health bar is made the first time the zombie is hurt.)

        // Walk: step through the baked frames (feet and arms swap), with a tiny
        // up-and-down on each step. Each zombie starts at a different point.
        let step = 0.11
        zombie.run(.sequence([
            .wait(forDuration: Double.random(in: 0...0.44)),
            .group([
                .repeatForever(.animate(with: body.frames, timePerFrame: step, resize: false, restore: false)),
                .repeatForever(.sequence([
                    .scaleY(to: 0.97, duration: step * 2),
                    .scaleY(to: 1.02, duration: step * 2)
                ]))
            ])
        ]), withKey: "shamble")

        world.addChild(zombie)
        zombies.append(Zombie(node: zombie, type: type, lane: lane))
    }

    // MARK: Movement

    func move(deltaTime: TimeInterval) {
        let lanes = path.lanes
        // Work backward so removing a zombie doesn't shift
        // the indexes of zombies we still need to update.
        for index in zombies.indices.reversed() {
            let zombie = zombies[index].node
            let waypoints = lanes[min(zombies[index].lane, lanes.count - 1)]
            // Ice tower slow: zombies crawl at iceSlowFactor of normal speed.
            var speedMultiplier: CGFloat = 1
            let slowed = zombies[index].slowTimer > 0
            if slowed {
                zombies[index].slowTimer -= deltaTime
                speedMultiplier = zombies[index].slowFactor
            }
            // Slowed zombies are tinted teal (a hit flash in progress wins).
            if zombie.action(forKey: "hitFlash") == nil {
                let target: CGFloat = slowed ? 0.55 : 0
                if zombie.colorBlendFactor != target {
                    zombie.color = .systemTeal
                    zombie.colorBlendFactor = target
                }
            }
            zombie.speed = speedMultiplier // slowed zombies shamble slower too
            var remainingMovement = speed * speedMultiplier * CGFloat(deltaTime)

            while remainingMovement > 0 {
                let waypointIndex = zombies[index].nextWaypointIndex

                guard waypointIndex < waypoints.count else {
                    // MH2D-55: reached the end of the path. Remove it first,
                    // then tell listeners (no reward is paid).
                    zombie.removeFromParent()
                    zombies.remove(at: index)
                    breachCount += 1
                    onZombieReachedBase?()
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

    // MARK: Progress along the road (used for target priorities)

    private var cachedLanes: [[CGPoint]] = []
    private var leftOver: [[CGFloat]] = []   // leftOver[lane][i] = road length from waypoint i to the base

    /// Recomputes the road lengths if the route changed. Call once per tick before asking.
    func prepareProgress() {
        guard cachedLanes != path.lanes else { return }
        cachedLanes = path.lanes
        leftOver = cachedLanes.map { lane in
            var out = [CGFloat](repeating: 0, count: lane.count)
            if lane.count >= 2 {
                for i in stride(from: lane.count - 2, through: 0, by: -1) {
                    out[i] = out[i + 1] + hypot(lane[i + 1].x - lane[i].x, lane[i + 1].y - lane[i].y)
                }
            }
            return out
        }
    }

    /// How far the zombie still has to walk to reach the base (smaller = further along).
    func remainingDistance(of zombie: Zombie) -> CGFloat {
        guard zombie.lane < leftOver.count else { return 0 }
        let waypoints = cachedLanes[zombie.lane]
        let next = min(zombie.nextWaypointIndex, waypoints.count - 1)
        guard next >= 0 else { return 0 }
        return hypot(waypoints[next].x - zombie.node.position.x, waypoints[next].y - zombie.node.position.y)
            + leftOver[zombie.lane][next]
    }

    /// Zombies store an index into the waypoints, so if the route moves they
    /// would snap to the new coordinates. Keep each zombie the same fraction
    /// of the way along its current segment on the new route.
    /// Call with the route as it was *before* the change (`oldWaypoints`).
    func remapProgress(from oldLanes: [[CGPoint]]) {
        let newLanes = path.lanes
        for index in zombies.indices {
            let lane = zombies[index].lane
            guard lane < oldLanes.count, lane < newLanes.count else { continue }
            let oldWaypoints = oldLanes[lane]
            let newWaypoints = newLanes[lane]
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

    func slow(at index: Int, duration: TimeInterval, factor: CGFloat = ZombieManager.iceSlowFactor) {
        guard zombies.indices.contains(index) else { return }
        // A stronger slow already running isn't weakened by a weaker pulse.
        if zombies[index].slowTimer > 0 { zombies[index].slowFactor = min(zombies[index].slowFactor, factor) }
        else { zombies[index].slowFactor = factor }
        zombies[index].slowTimer = max(zombies[index].slowTimer, duration)
    }

    /// MH2D-52: apply a projectile's damage to the zombie it hit. Health drops
    /// by exactly `damage`; the health bar and a short white flash show it.
    /// A killed zombie is removed and pays its reward (MH2D-53); the death
    /// effect is MH2D-54.
    func applyDamage(at index: Int, damage: Int, type: DamageType = .bullet) {
        guard zombies.indices.contains(index) else { return }
        // MH2D-95: this zombie's resistance to the damage type scales the hit
        // (a real hit always does at least 1).
        let multiplier = zombies[index].type.damageMultiplier(for: type)
        let dealt = damage > 0 ? max(1, Int((Double(damage) * multiplier).rounded())) : 0
        zombies[index].health = max(0, zombies[index].health - dealt)
        let state = zombies[index]
        updateHealthBar(of: state)
        flashHit(state.node, color: type == .bullet ? .white : type.effectColor)

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
    private func playDeathEffect(on node: SKSpriteNode, reward: Int) {
        node.removeAllActions()
        node.speed = 1
        node.zRotation = 0
        node.yScale = 1
        node.childNode(withName: "healthBack")?.isHidden = true
        node.color = .systemRed
        node.colorBlendFactor = 0.8
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

    /// MH2D-52: small health bar above the zombie (red = missing health).
    private func makeHealthBar(on zombie: SKSpriteNode) -> SKSpriteNode {
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
        zombie.addChild(barBack)
        return barBack
    }

    /// Resize the green part of the bar to health / maxHealth and show it.
    private func updateHealthBar(of zombie: Zombie) {
        let back = zombie.node.childNode(withName: "healthBack") as? SKSpriteNode ?? makeHealthBar(on: zombie.node)
        guard let fill = back.childNode(withName: "healthFill") as? SKSpriteNode else { return }
        back.isHidden = false
        let fraction = CGFloat(zombie.health) / CGFloat(max(1, zombie.maxHealth))
        fill.size.width = ZombieManager.healthBarWidth * fraction
    }

    /// Brief white flash so each hit is visible.
    private func flashHit(_ node: SKSpriteNode, color: UIColor = .white) {
        node.removeAction(forKey: "hitFlash")
        node.run(.sequence([
            .run { node.color = color; node.colorBlendFactor = 0.85 },
            .wait(forDuration: 0.08),
            .run { node.colorBlendFactor = 0 } // move() puts the slow tint back if needed
        ]), withKey: "hitFlash")
    }
    
    // Checks if wave has fully spawned and if there is no zombies left.
    var isWaveComplete: Bool {
        zombiesSpawnedThisWave >= zombiesPerWave &&
        zombies.isEmpty
    }
    
    private(set) var currentWave: Int = 1
    
    var totalWaves: Int {
        ZombieManager.totalWaveCount
    }
    
    private var hasAnnouncedWaveCompletion: Bool = false
    
    /// Win screen -> Continue: keep playing past the last wave.
    func continueAfterVictory() {
        isEndless = true
        currentWave += 1
        zombiesSpawnedThisWave = 0
        spawnTimer = 0
        hasAnnouncedWaveCompletion = false
        print("Starting Wave \(currentWave)")
    }

    func checkWaveCompletion() {
        guard isWaveComplete && !hasAnnouncedWaveCompletion else {
            return
        }

        hasAnnouncedWaveCompletion = true
        print("Wave \(currentWave) Complete")
        onWaveCompleted?(currentWave)

        // The last wave is done: tell the scene (win screen) and wait. The wave
        // only advances if the player chooses Continue (`continueAfterVictory`).
        if currentWave >= ZombieManager.totalWaveCount && !isEndless {
            print("All waves complete!")
            onAllWavesCompleted?()
            return
        }

        currentWave += 1
        zombiesSpawnedThisWave = 0
        spawnTimer = 0
        hasAnnouncedWaveCompletion = false

        print("Starting Wave \(currentWave)")
    }
    
    
}
