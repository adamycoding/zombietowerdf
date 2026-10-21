//
//  ProjectileSpec.swift
//  Combat
//
//  MH2D-12 / MH2D-45: the collision shapes and the numbers for each tower's
//  shots. Every shape is a circle (Bloons-style).
//

import SpriteKit
import UIKit

/// MH2D-45: a zombie's "can be hit" circle, centered on its node.
struct Hurtbox { var radius: CGFloat }
/// MH2D-45: a projectile's "deals a hit" circle, centered on its node.
struct Hitbox { var radius: CGFloat }

/// Look and numbers for one tower type's projectile.
struct ProjectileSpec {
    var radius: CGFloat          // hitbox radius (also the drawn size)
    var speed: CGFloat           // points per second
    var color: UIColor
    var range: CGFloat           // how far the tower can shoot
    var fireInterval: TimeInterval
    var lifetime: TimeInterval   // seconds before a missed shot disappears
    var damage: Int              // health removed from a zombie per hit (MH2D-52)
}

extension TowerType {
    /// TEMP values: when MH2D-9 (real tower stats/art) lands, replace this
    /// with each tower's real numbers.
    var spec: ProjectileSpec {
        switch self {
        case .soldier:
            return ProjectileSpec(radius: 4, speed: 380, color: .systemYellow, range: 80, fireInterval: 0.6, lifetime: 1.2, damage: 1)
        case .sniper:
            return ProjectileSpec(radius: 3, speed: 700, color: .white, range: 168, fireInterval: 1.6, lifetime: 1.2, damage: 3)
        case .ice:
            return ProjectileSpec(radius: 7, speed: 240, color: .systemCyan, range: 68, fireInterval: 1.0, lifetime: 1.5, damage: 0)
        }
    }
}
