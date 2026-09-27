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

final class GameScene: SKScene {

    // MARK: - MH2D-34: Scaffolding

    /// Root node everything gameplay-related gets added to. Keeping a
    /// single "world" node (instead of adding directly to the scene) makes
    /// it trivial to add camera panning/zooming later without touching
    /// every other piece of code.
    private let worldNode = SKNode()

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

        addChild(worldNode)

        setUpDebugStats(in: view) // remove once you trust the loop; handy while building it
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
        // Example placeholder — remove once real systems are wired in:
        // worldNode.enumerateChildNodes(withName: "//zombie_*") { node, _ in
        //     (node as? ZombieNode)?.tick(deltaTime: deltaTime)
        // }
        tickCount += 1
        updateDebugStats()
    }
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        debugLabel?.position = CGPoint(x: 10, y: self.size.height - 40)
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
        debugLabel?.text = "fixed ticks: \(tickCount)"
    }
}
