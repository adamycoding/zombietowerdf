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
    var damageType: DamageType = .bullet // MH2D-95: what kind of damage it deals
    var blastRadius: CGFloat = 0         // > 0: hits every zombie in this radius (area damage)
    var chainCount: Int = 0              // > 0: lightning that hits this many zombies in a row (Tesla)
    var chainRange: CGFloat = 0          // how far lightning can jump to the next zombie
    var wireDurability: Int = 0          // > 0: lays barbed wire that survives this many zombie hits
    var slowFactor: CGFloat = 0.45       // ice: zombies move at this share of normal speed (lower = stronger)
    var slowDuration: TimeInterval = 2.0 // ice: how long one pulse keeps zombies slowed

    /// Range so large it covers the whole map. Such a tower can hit anything it can SEE
    /// (obstacles still block the shot) so there is no range circle to draw.
    static let globalRange: CGFloat = 4000
    var isGlobalRange: Bool { range >= ProjectileSpec.globalRange }
}

extension TowerType {
    /// TEMP values: when MH2D-9 (real tower stats/art) lands, replace this
    /// with each tower's real numbers.
    var spec: ProjectileSpec {
        switch self {
        case .soldier:
            return ProjectileSpec(radius: 4, speed: 380, color: .systemYellow, range: 80, fireInterval: 0.6, lifetime: 1.2, damage: 1)
        case .gunner:
            // Machine gun: weaker shots than the Soldier but 2.4x the fire rate.
            return ProjectileSpec(radius: 3, speed: 420, color: .systemYellow, range: 75, fireInterval: 0.25, lifetime: 1.0, damage: 1)
        case .sniper:
            return ProjectileSpec(radius: 3, speed: 700, color: .white, range: ProjectileSpec.globalRange, fireInterval: 1.6, lifetime: 2.0, damage: 3)
        case .grenadier:
            return ProjectileSpec(radius: 6, speed: 260, color: .systemOrange, range: 110, fireInterval: 2.2, lifetime: 1.6, damage: 2, damageType: .explosive, blastRadius: 48)
        case .flamethrower:
            // Very short range, fast burst of flames.
            return ProjectileSpec(radius: 5, speed: 220, color: UIColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 1), range: 55, fireInterval: 0.3, lifetime: 0.3, damage: 1, damageType: .fire)
        case .tesla:
            // Instant lightning: hits the nearest zombie, then jumps to 2 more.
            return ProjectileSpec(radius: 0, speed: 0, color: UIColor(red: 0.72, green: 0.62, blue: 1.0, alpha: 1), range: 90, fireInterval: 1.4, lifetime: 0, damage: 2, damageType: .electric, chainCount: 3, chainRange: 55)
        case .trapper:
            // Lays barbed wire on the road; each patch survives 6 zombie hits.
            return ProjectileSpec(radius: 0, speed: 0, color: .lightGray, range: 100, fireInterval: 3.5, lifetime: 0, damage: 1, damageType: .trap, wireDurability: 6)
        case .ice:
            return ProjectileSpec(radius: 7, speed: 240, color: .systemCyan, range: 68, fireInterval: 1.0, lifetime: 1.5, damage: 0, damageType: .frost)
        }
    }
}
