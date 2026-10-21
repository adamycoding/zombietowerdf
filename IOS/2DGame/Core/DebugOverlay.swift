//
//  DebugOverlay.swift
//  Core
//
//  MH2D-12 test helpers: the hitbox overlay switch and the circle outlines
//  it shows. Zombies, projectiles and towers all draw their debug circles
//  through here.
//

import SpriteKit
import UIKit

enum DebugOverlay {
    /// When true, hurtboxes, hitboxes and tower ranges are drawn.
    static var showHitboxes = false

    /// Names of the debug circle nodes, so the toggle can find them.
    static let circleNames = ["hurtboxDebug", "hitboxDebug", "rangeDebug"]

    static func makeCircle(radius: CGFloat, color: UIColor, name: String) -> SKShapeNode {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.name = name
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 1.5
        ring.zPosition = 5
        ring.isHidden = !showHitboxes
        return ring
    }
}
