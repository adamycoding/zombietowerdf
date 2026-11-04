//
//  WaveDefinition.swift
//  2DGame
//
//  Created by Adam Yang on 10/19/26.
//

import Foundation
import UIKit

enum ZombieType: CaseIterable {
    case normal
    case runner   // fast and fragile
    case brute    // slow, big, very tough

    var displayName: String {
        switch self {
        case .normal: return "Walker"
        case .runner: return "Runner"
        case .brute: return "Brute"
        }
    }
    /// Hit points.
    var health: Int {
        switch self {
        case .normal: return ZombieManager.normalHealth
        case .runner: return 2
        case .brute: return 12
        }
    }
    /// Money paid when it is killed.
    var reward: Int {
        switch self {
        case .normal: return ZombieManager.normalReward
        case .runner: return 6
        case .brute: return 20
        }
    }
    /// Walking speed compared with a normal zombie.
    var speedFactor: CGFloat {
        switch self {
        case .normal: return 1
        case .runner: return 1.7
        case .brute: return 0.6
        }
    }
    /// Drawn size compared with a normal zombie.
    var scale: CGFloat {
        switch self {
        case .normal: return 1
        case .runner: return 0.85
        case .brute: return 1.3
        }
    }
    /// Colour wash over the (same) zombie art, so each kind is easy to tell apart.
    var tint: UIColor {
        switch self {
        case .normal: return .systemTeal
        case .runner: return UIColor(red: 0.95, green: 0.85, blue: 0.2, alpha: 1)
        case .brute: return UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1)
        }
    }
    var tintBlend: CGFloat { 0 }   // identity now comes from the drawn art, not a tint

    /// Skin colour of the drawn zombie.
    var skinColor: UIColor {
        switch self {
        case .normal: return .systemGreen
        case .runner: return UIColor(red: 0.78, green: 0.86, blue: 0.30, alpha: 1)
        case .brute:  return UIColor(red: 0.30, green: 0.45, blue: 0.30, alpha: 1)
        }
    }

    /// Clothing colour of the drawn zombie.
    var shirtColor: UIColor {
        switch self {
        case .normal: return UIColor(red: 0.39, green: 0.36, blue: 0.27, alpha: 1)
        case .runner: return UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
        case .brute:  return UIColor(red: 0.35, green: 0.12, blue: 0.12, alpha: 1)
        }
    }
}

// this defines how many zmobies per wave and also spawning intervals (how fast they spawn).
struct WaveDefinition {
    let zombieTypes: [ZombieType]
    let spawnInterval: TimeInterval

    var zombieCount: Int {
        zombieTypes.count
    }
}
