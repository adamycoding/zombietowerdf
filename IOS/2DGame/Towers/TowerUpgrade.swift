//
//  TowerUpgrade.swift
//  Towers
//
//  MH2D-17: the rules for upgrading a placed tower. Every tower can be
//  upgraded up to `maxTier` times. Each tier makes it fire faster and reach
//  further, and from tier 2 on it also hits harder. Costs and numbers are all
//  here so they are easy to tune (and so a later upgrade-path system can
//  swap in its own tables).
//

import Foundation

enum TowerUpgrade {

    /// How many times a tower can be upgraded (tier 0 is the base tower).
    static let maxTier = 3

    /// Each tier multiplies the time between shots by this (faster fire).
    static let fireIntervalFactor = 0.88
    /// Each tier multiplies the range by this.
    static let rangeFactor: CGFloat = 1.07
    /// Extra durability per tier for barbed wire.
    static let wireDurabilityPerTier = 2

    /// What upgrading to `tier` (1...maxTier) costs, as a share of the tower's price.
    private static let costShare: [Double] = [0.5, 0.75, 1.0]

    /// Cost to upgrade a tower of this type up to `tier`. Rounded to $5.
    static func cost(of type: TowerType, toTier tier: Int) -> Int {
        guard (1...maxTier).contains(tier) else { return 0 }
        let raw = Double(type.cost) * costShare[tier - 1]
        return Int((raw / 5).rounded()) * 5
    }

    /// Total money put into a tower: its price plus every upgrade so far.
    static func moneySpent(on type: TowerType, tier: Int) -> Int {
        var total = type.cost
        if tier >= 1 { for t in 1...tier { total += cost(of: type, toTier: t) } }
        return total
    }

    /// The tower's numbers at a given tier.
    static func spec(for type: TowerType, tier: Int) -> ProjectileSpec {
        var spec = type.spec
        let t = min(max(0, tier), maxTier)
        guard t > 0 else { return spec }
        spec.fireInterval *= pow(fireIntervalFactor, Double(t))
        if !spec.isGlobalRange { spec.range *= pow(rangeFactor, CGFloat(t)) }
        if type == .ice { // each tier slows harder and for longer
            spec.slowFactor *= pow(0.85, CGFloat(t))
            spec.slowDuration += 0.4 * Double(t)
        }
        if spec.damage > 0 { spec.damage += max(0, t - 1) } // +1 at tier 2 and again at tier 3
        if spec.wireDurability > 0 { spec.wireDurability += wireDurabilityPerTier * t }
        return spec
    }

    /// One row of the upgrade panel: "Damage 1 -> 2".
    struct StatLine {
        let name: String
        let current: String
        let next: String?   // nil at max tier or when this stat doesn't change
    }

    /// Rows for the panel: the tower's current numbers and what the next tier gives.
    static func statLines(for type: TowerType, tier: Int) -> [StatLine] {
        let now = spec(for: type, tier: tier)
        let upcoming: ProjectileSpec? = tier < maxTier ? spec(for: type, tier: tier + 1) : nil

        func line(_ name: String, _ a: String, _ b: String?) -> StatLine {
            StatLine(name: name, current: a, next: (b != nil && b != a) ? b : nil)
        }
        func shots(_ s: ProjectileSpec) -> String { String(format: "%.1f/s", 1 / s.fireInterval) }

        var lines: [StatLine] = []
        if now.damage > 0 {
            lines.append(line("Damage", "\(now.damage)", upcoming.map { "\($0.damage)" }))
        }
        if now.isGlobalRange {
            lines.append(line("Range", "Global", nil))
        } else {
            lines.append(line("Range", "\(Int(now.range.rounded()))", upcoming.map { "\(Int($0.range.rounded()))" }))
        }
        // Ice and Barbed Wire don't "shoot": show what their timer actually does.
        func seconds(_ s: ProjectileSpec) -> String { String(format: "%.1fs", s.fireInterval) }
        if type == .ice {
            lines.append(line("Pulse every", seconds(now), upcoming.map { seconds($0) }))
            func slowText(_ s: ProjectileSpec) -> String { "\(Int(((1 - s.slowFactor) * 100).rounded()))%" }
            func durText(_ s: ProjectileSpec) -> String { String(format: "%.1fs", s.slowDuration) }
            lines.append(line("Slow", slowText(now), upcoming.map { slowText($0) }))
            lines.append(line("Slow time", durText(now), upcoming.map { durText($0) }))
        } else if type == .trapper {
            lines.append(line("Lays wire every", seconds(now), upcoming.map { seconds($0) }))
        } else {
            lines.append(line("Speed", shots(now), upcoming.map { shots($0) }))
        }
        if now.wireDurability > 0 {
            lines.append(line("Wire", "\(now.wireDurability)", upcoming.map { "\($0.wireDurability)" }))
        }
        return lines
    }
}
