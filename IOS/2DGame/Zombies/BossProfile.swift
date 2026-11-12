import UIKit

/// Balance and appearance for each tenth-wave boss. The first boss uses
/// megaBoss.health/reward/scale from WaveDefinition.swift as its base.
struct BossProfile {
    let tier: Int

    init(wave: Int) {
        tier = max(1, wave / WaveDefinition.bossInterval)
    }

    // Double health each milestone; bound the exponent for very long endless runs.
    var health: Int { ZombieType.megaBoss.health * (1 << min(tier - 1, 20)) }
    var reward: Int { ZombieType.megaBoss.reward * tier }
    var scale: CGFloat { min(3.2, ZombieType.megaBoss.scale + CGFloat(tier - 1) * 0.15) }
    var style: Int { (tier - 1) % 4 }

    var skinColor: UIColor {
        switch style {
        case 0: return UIColor(red: 0.5, green: 0.2, blue: 0.65, alpha: 1)
        case 1: return UIColor(red: 0.2, green: 0.55, blue: 0.8, alpha: 1)
        case 2: return UIColor(red: 0.8, green: 0.2, blue: 0.12, alpha: 1)
        default: return UIColor(red: 0.2, green: 0.65, blue: 0.3, alpha: 1)
        }
    }
    var armorColor: UIColor {
        switch style {
        case 0: return .darkGray
        case 1: return .systemIndigo
        case 2: return UIColor(white: 0.15, alpha: 1)
        default: return .brown
        }
    }
    var accentColor: UIColor {
        switch style {
        case 0: return .systemYellow
        case 1: return .cyan
        case 2: return .systemOrange
        default: return .systemPink
        }
    }
}
