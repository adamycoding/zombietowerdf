//
//  TowerUpgrade.swift
//  Towers
//
//  Bloons-style upgrades. Every tower has THREE upgrade paths, each with five
//  levels. A tower can go all the way (level 5) down ONE path, and up to level
//  2 down a SECOND path. The third path is then locked. Costs, names and
//  numbers are all here so they are easy to tune.
//

import Foundation
import UIKit

enum TowerUpgrade {

    static let pathCount = 3
    /// The deepest any one path can go.
    static let maxLevel = 5
    /// Once one path is past this level, the other paths stop at it.
    static let secondaryCap = 2

    // MARK: Paths

    /// What a path improves.
    enum Theme { case rate, power, reach, special }

    static func paths(for type: TowerType) -> [(name: String, theme: Theme)] {
        switch type {
        case .ice:          return [("Deep Freeze", .special), ("Wide Chill", .reach), ("Rapid Pulse", .rate)]
        case .trapper:      return [("Heavy Wire", .special), ("Sharp Barbs", .power), ("Quick Lay", .rate)]
        case .tesla:        return [("Long Arc", .special), ("High Voltage", .power), ("Overcharge", .rate)]
        case .grenadier:    return [("Big Blast", .special), ("Heavy Shell", .power), ("Quick Load", .rate)]
        case .sniper:       return [("Armor Piercing", .power), ("Rapid Bolt", .rate), ("Marksman", .special)]
        case .flamethrower: return [("Hotter Flame", .power), ("Long Burn", .reach), ("Quick Burst", .rate)]
        default:            return [("Rapid Fire", .rate), ("Heavy Rounds", .power), ("Long Range", .reach)]
        }
    }

    static func pathName(for type: TowerType, path: Int) -> String {
        paths(for: type)[path].name
    }

    private static let roman = ["", "I", "II", "III", "IV", "V"]

    /// Name of the upgrade that takes `path` to `level`, e.g. "Deep Freeze III".
    static func upgradeName(for type: TowerType, path: Int, level: Int) -> String {
        "\(pathName(for: type, path: path)) \(roman[min(max(level, 0), maxLevel)])"
    }

    // MARK: Rules

    /// Can this path go up one more level?
    static func canUpgrade(levels: [Int], path: Int) -> Bool {
        guard levels.indices.contains(path), levels[path] < maxLevel else { return false }
        let next = levels[path] + 1
        let others = levels.indices.filter { $0 != path }.map { levels[$0] }
        if levels[path] == 0 && others.filter({ $0 > 0 }).count >= 2 { return false } // third path locked
        if next > secondaryCap && others.contains(where: { $0 > secondaryCap }) { return false }
        return true
    }

    /// Each level costs this share of the tower's price.
    private static let costShare: [Double] = [0.4, 0.6, 0.9, 1.6, 3.0]

    /// Cost to take a path to `level`. Rounded to $5.
    static func cost(of type: TowerType, toLevel level: Int) -> Int {
        guard (1...maxLevel).contains(level) else { return 0 }
        return max(5, Int((Double(type.cost) * costShare[level - 1] / 5).rounded()) * 5)
    }

    /// Price of the next level on `path`, or nil when it is maxed or locked.
    static func nextCost(for type: TowerType, levels: [Int], path: Int) -> Int? {
        guard canUpgrade(levels: levels, path: path) else { return nil }
        return cost(of: type, toLevel: levels[path] + 1)
    }

    /// Total money put into a tower: its price plus every upgrade so far.
    static func moneySpent(on type: TowerType, levels: [Int]) -> Int {
        var total = type.cost
        for n in levels where n > 0 { for l in 1...n { total += cost(of: type, toLevel: l) } }
        return total
    }

    // MARK: Numbers

    /// The tower's numbers with these upgrades.
    static func spec(for type: TowerType, levels: [Int]) -> ProjectileSpec {
        var spec = type.spec
        for (path, info) in paths(for: type).enumerated() where levels.indices.contains(path) && levels[path] > 0 {
            apply(info.theme, level: levels[path], type: type, to: &spec)
        }
        return spec
    }

    private static func apply(_ theme: Theme, level n: Int, type: TowerType, to spec: inout ProjectileSpec) {
        let nd = Double(n), nf = CGFloat(n)
        let capstone = n == maxLevel
        switch theme {
        case .rate:
            spec.fireInterval *= pow(0.86, nd) * (capstone ? 0.85 : 1)
        case .power:
            if spec.damage > 0 { spec.damage += (n + 1) / 2 + (capstone ? 2 : 0) }
            if spec.wireDurability > 0 { spec.wireDurability += 3 * n }
        case .reach:
            if !spec.isGlobalRange { spec.range *= pow(1.08, nf) * (capstone ? 1.1 : 1) }
        case .special:
            switch type {
            case .ice:
                spec.slowFactor *= pow(0.85, nf)
                spec.slowDuration += 0.5 * nd
            case .trapper:
                spec.wireDurability += 4 * n
            case .tesla:
                spec.chainCount += n
                spec.chainRange += 15 * nf
            case .grenadier:
                spec.blastRadius += 10 * nf
            case .sniper:
                if spec.damage > 0 { spec.damage += n }
                spec.fireInterval *= pow(0.95, nd)
            default:
                break
            }
        }
    }

    /// One row of the upgrade panel.
    struct StatLine {
        let name: String
        let current: String
        let next: String?
    }

    /// Rows for the panel: the tower's current numbers.
    static func statLines(for type: TowerType, levels: [Int]) -> [StatLine] {
        let now = spec(for: type, levels: levels)
        func line(_ name: String, _ a: String) -> StatLine { StatLine(name: name, current: a, next: nil) }
        func seconds(_ s: ProjectileSpec) -> String { String(format: "%.2fs", s.fireInterval) }

        var lines: [StatLine] = []
        if now.damage > 0 { lines.append(line("Damage", "\(now.damage)")) }
        lines.append(line("Range", now.isGlobalRange ? "Global" : "\(Int(now.range.rounded()))"))
        if type == .ice {
            lines.append(line("Pulse every", seconds(now)))
            lines.append(line("Slow", "\(Int(((1 - now.slowFactor) * 100).rounded()))%"))
            lines.append(line("Slow time", String(format: "%.1fs", now.slowDuration)))
        } else if type == .trapper {
            lines.append(line("Lays wire every", seconds(now)))
        } else {
            lines.append(line("Speed", String(format: "%.1f/s", 1 / now.fireInterval)))
        }
        if now.wireDurability > 0 { lines.append(line("Wire", "\(now.wireDurability)")) }
        return lines
    }
}
