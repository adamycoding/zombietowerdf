//
//  GameViewController.swift
//  ZombieTD
//
//  Replaces the template's default GameViewController.swift.
//
//  Two changes from the template:
//   1. Builds GameScene() directly in code instead of loading it from
//      GameScene.sks — matches how GameScene.swift's own scaffolding
//      (worldNode, Layer enum) is written to work, and keeps the whole
//      map/grid definition in code rather than split across a visual
//      editor file and Swift.
//   2. Adds NotificationCenter observers for background/foreground so
//      MH2D-37 (app lifecycle handling) actually fires — the UIKit
//      equivalent of SwiftUI's scenePhase, since this project uses
//      Storyboards/UIKit rather than SwiftUI.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {

    private var gameScene: GameScene?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let skView = self.view as? SKView else { return }

        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true
        startNewGame(in: skView)

        // MH2D-37: wire lifecycle notifications to the scene's pause/resume.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    /// MH2D-82: builds a brand-new scene (money, waves, base health, towers
    /// all start fresh). Called at launch and when the player taps Retry.
    private func startNewGame(in skView: SKView) {
        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        scene.onRetryRequested = { [weak self, weak skView] in
            guard let skView else { return }
            self?.startNewGame(in: skView)
        }
        gameScene = scene
        skView.presentScene(scene)
    }

    @objc private func appDidEnterBackground() {
        gameScene?.handleAppDidEnterBackground()
    }

    @objc private func appWillEnterForeground() {
        gameScene?.handleAppWillEnterForeground()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
