//
//  MapDefinition.swift
//  Map
//
//  MH2D-26: the data for one map. Each lane is a route a zombie can walk,
//  written as points in 0...1 map space (0,0 = bottom-left of the play area).
//  Maps with several lanes send zombies down all of them in turn, so they are
//  harder: the same towers have to cover more roads.
//

import CoreGraphics
import SpriteKit

/// How a map looks: colours and the kind of trees. Each map has its own, so
/// they don't all look like the same meadow.
struct MapTheme {
    enum TreeStyle { case oak, pine, cactus, dead }

    let ground: SKColor
    let tuft: SKColor
    let road: SKColor
    let roadEdge: SKColor
    let foliage: SKColor
    let trunk: SKColor
    let rock: SKColor
    let rockEdge: SKColor
    let water: SKColor
    let shore: SKColor
    let boulder: SKColor
    let tree: TreeStyle
    let snow: Bool

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> SKColor {
        SKColor(red: r, green: g, blue: b, alpha: a)
    }

    static let meadow = MapTheme(
        ground: c(0.39, 0.49, 0.25), tuft: c(0.28, 0.39, 0.19, 0.65),
        road: c(0.77, 0.70, 0.46), roadEdge: c(0.58, 0.52, 0.32),
        foliage: c(0.34, 0.49, 0.24), trunk: c(0.39, 0.28, 0.17),
        rock: c(0.49, 0.51, 0.44), rockEdge: c(0.28, 0.31, 0.25),
        water: c(0.30, 0.53, 0.57), shore: c(0.49, 0.62, 0.39),
        boulder: c(0.55, 0.56, 0.50), tree: .oak, snow: false)

    static let autumn = MapTheme(
        ground: c(0.47, 0.40, 0.21), tuft: c(0.62, 0.31, 0.10, 0.7),
        road: c(0.66, 0.54, 0.38), roadEdge: c(0.45, 0.35, 0.22),
        foliage: c(0.88, 0.45, 0.14), trunk: c(0.36, 0.24, 0.14),
        rock: c(0.52, 0.46, 0.40), rockEdge: c(0.30, 0.25, 0.20),
        water: c(0.34, 0.50, 0.55), shore: c(0.60, 0.48, 0.24),
        boulder: c(0.56, 0.49, 0.42), tree: .oak, snow: false)

    static let desert = MapTheme(
        ground: c(0.87, 0.74, 0.47), tuft: c(0.62, 0.45, 0.20, 0.7),
        road: c(0.58, 0.44, 0.31), roadEdge: c(0.40, 0.29, 0.19),
        foliage: c(0.30, 0.56, 0.31), trunk: c(0.30, 0.45, 0.22),
        rock: c(0.76, 0.55, 0.37), rockEdge: c(0.52, 0.34, 0.22),
        water: c(0.18, 0.62, 0.72), shore: c(0.42, 0.66, 0.30),
        boulder: c(0.80, 0.58, 0.38), tree: .cactus, snow: false)

    static let snow = MapTheme(
        ground: c(0.89, 0.94, 0.98), tuft: c(0.62, 0.73, 0.84, 0.8),
        road: c(0.60, 0.63, 0.68), roadEdge: c(0.43, 0.47, 0.54),
        foliage: c(0.16, 0.38, 0.30), trunk: c(0.30, 0.22, 0.16),
        rock: c(0.62, 0.68, 0.75), rockEdge: c(0.38, 0.44, 0.52),
        water: c(0.62, 0.84, 0.94), shore: c(0.97, 0.98, 1.0),
        boulder: c(0.68, 0.76, 0.84), tree: .pine, snow: true)

    static let swamp = MapTheme(
        ground: c(0.22, 0.34, 0.27), tuft: c(0.10, 0.20, 0.13, 0.8),
        road: c(0.43, 0.34, 0.22), roadEdge: c(0.26, 0.19, 0.12),
        foliage: c(0.33, 0.42, 0.22), trunk: c(0.32, 0.27, 0.21),
        rock: c(0.34, 0.42, 0.33), rockEdge: c(0.16, 0.24, 0.17),
        water: c(0.20, 0.33, 0.26), shore: c(0.35, 0.45, 0.20),
        boulder: c(0.30, 0.40, 0.30), tree: .dead, snow: false)

    static let volcano = MapTheme(
        ground: c(0.21, 0.18, 0.19), tuft: c(0.55, 0.18, 0.08, 0.8),
        road: c(0.32, 0.27, 0.28), roadEdge: c(0.82, 0.30, 0.08),
        foliage: c(0.18, 0.14, 0.14), trunk: c(0.13, 0.10, 0.10),
        rock: c(0.36, 0.31, 0.31), rockEdge: c(0.12, 0.09, 0.09),
        water: c(0.97, 0.42, 0.10), shore: c(0.30, 0.10, 0.05),
        boulder: c(0.28, 0.24, 0.25), tree: .dead, snow: false)
}

struct MapDefinition {
    enum Difficulty: String {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case hard = "Hard"
    }

    let name: String
    let difficulty: Difficulty
    let blurb: String
    /// Every route, start to base. All lanes should end at the base.
    let lanes: [[CGPoint]]
    /// How much of the play area the roads use (1 = all of it). Smaller maps
    /// are tighter and leave more open grass around the edge.
    let area: CGFloat
    let trees: [CGPoint]
    let rocks: [CGPoint]
    /// Where the pond sits (bottom-centre of the pond), or nil for none.
    let pond: CGPoint?
    /// True = the road is drawn as smooth curves through the points; false = sharp corners.
    let curvy: Bool
    /// Extra trees scattered around (kept clear of the road).
    let extraTrees: Int
    /// Big rocks that stand in the way. Towers can't be built on them and they
    /// block shots (see GamePath.isBlocked).
    let boulders: [CGPoint]
    let theme: MapTheme

    var laneCount: Int { lanes.count }

    private static func pts(_ values: [(CGFloat, CGFloat)]) -> [CGPoint] {
        values.map { CGPoint(x: $0.0, y: $0.1) }
    }

    // MARK: The maps

    static let switchback = MapDefinition(
        name: "Winding Creek",
        difficulty: .beginner,
        blurb: "One long, lazy, curving road. Lots of time to shoot.",
        lanes: [pts([(0, 0.80), (0.20, 0.80), (0.35, 0.55), (0.20, 0.30), (0.40, 0.12),
                     (0.65, 0.20), (0.75, 0.50), (0.60, 0.78), (0.85, 0.85), (1, 0.60)])],
        area: 1,
        trees: pts([(0.05, 0.50), (0.93, 0.25), (0.50, 0.92), (0.92, 0.95)]),
        rocks: pts([(0.50, 0.40), (0.10, 0.10), (0.97, 0.40)]),
        pond: CGPoint(x: 0.52, y: 0.60),
        curvy: true,
        extraTrees: 14,
        boulders: pts([(0.50, 0.50), (0.08, 0.50), (0.92, 0.25), (0.45, 0.93)]),
        theme: .autumn
    )

    static let meadowRun = MapDefinition(
        name: "Meadow Run",
        difficulty: .intermediate,
        blurb: "A small, tight map. Zombies are on you fast.",
        lanes: [pts([(0, 0.40), (0.24, 0.40), (0.24, 0.73), (0.48, 0.73), (0.48, 0.32), (1, 0.32)])],
        area: 0.8,
        trees: pts([(0.08, 0.08), (0.12, 0.88), (0.59, 0.88), (0.88, 0.88), (0.42, 0.04)]),
        rocks: pts([(0.27, 0.05), (0.74, 0.86), (0.95, 0.08)]),
        pond: CGPoint(x: 0.77, y: 0),
        curvy: false,
        extraTrees: 6,
        boulders: pts([(0.65, 0.58), (0.36, 0.17), (0.12, 0.65)]),
        theme: .meadow
    )

    static let crossroads = MapDefinition(
        name: "X Marks the Spot",
        difficulty: .intermediate,
        blurb: "Two curving roads cross in the middle, then meet at the base.",
        lanes: [
            pts([(0, 0.85), (0.35, 0.75), (0.50, 0.50), (0.65, 0.25), (0.85, 0.30), (1, 0.50)]),
            pts([(0, 0.15), (0.35, 0.25), (0.50, 0.50), (0.65, 0.75), (0.85, 0.70), (1, 0.50)])
        ],
        area: 0.85,
        trees: pts([(0.05, 0.50), (0.60, 0.95), (0.60, 0.05), (0.95, 0.92), (0.95, 0.08)]),
        rocks: pts([(0.25, 0.50), (0.78, 0.50), (0.10, 0.95)]),
        pond: CGPoint(x: 0.30, y: 0.46),
        curvy: true,
        extraTrees: 10,
        boulders: pts([(0.22, 0.50), (0.78, 0.50), (0.50, 0.90), (0.50, 0.10)]),
        theme: .desert
    )

    static let bullseye = MapDefinition(
        name: "Bullseye",
        difficulty: .hard,
        blurb: "A huge spiral that winds in to the middle.",
        lanes: [pts([(0, 0.15), (0.50, 0.07), (0.93, 0.20), (0.97, 0.60), (0.80, 0.92),
                     (0.40, 0.95), (0.10, 0.82), (0.05, 0.50), (0.20, 0.33), (0.50, 0.30),
                     (0.78, 0.40), (0.80, 0.65), (0.55, 0.75), (0.30, 0.68), (0.30, 0.50),
                     (0.50, 0.50)])],
        area: 0.95,
        trees: pts([(0.50, 0.62), (0.40, 0.40), (0.02, 0.95), (0.98, 0.05)]),
        rocks: pts([(0.65, 0.52), (0.12, 0.58), (0.60, 0.15)]),
        pond: nil,
        curvy: true,
        extraTrees: 10,
        boulders: [],
        theme: .snow
    )

    static let threeRivers = MapDefinition(
        name: "Three Rivers",
        difficulty: .hard,
        blurb: "Three winding roads from three sides meet near the base.",
        lanes: [
            pts([(0.15, 1), (0.20, 0.80), (0.42, 0.72), (0.58, 0.58), (0.70, 0.50), (1, 0.50)]),
            pts([(0, 0.50), (0.20, 0.40), (0.40, 0.58), (0.55, 0.42), (0.70, 0.50), (1, 0.50)]),
            pts([(0.15, 0), (0.20, 0.20), (0.42, 0.28), (0.58, 0.42), (0.70, 0.50), (1, 0.50)])
        ],
        area: 0.9,
        trees: pts([(0.05, 0.85), (0.05, 0.15), (0.40, 0.92), (0.40, 0.08), (0.88, 0.80), (0.88, 0.20)]),
        rocks: pts([(0.45, 0.50), (0.80, 0.65), (0.80, 0.35)]),
        pond: CGPoint(x: 0.80, y: 0.02),
        curvy: true,
        extraTrees: 12,
        boulders: pts([(0.82, 0.78), (0.82, 0.22), (0.07, 0.72), (0.07, 0.28)]),
        theme: .swamp
    )

    static let gauntlet = MapDefinition(
        name: "Gauntlet",
        difficulty: .hard,
        blurb: "Four sharp roads, one base in the middle. Good luck.",
        lanes: [
            pts([(0, 0.78), (0.25, 0.78), (0.25, 0.50), (0.50, 0.50)]),
            pts([(1, 0.22), (0.75, 0.22), (0.75, 0.50), (0.50, 0.50)]),
            pts([(0.70, 1), (0.70, 0.78), (0.50, 0.78), (0.50, 0.50)]),
            pts([(0.30, 0), (0.30, 0.22), (0.50, 0.22), (0.50, 0.50)])
        ],
        area: 1,
        trees: pts([(0.05, 0.30), (0.95, 0.70), (0.12, 0.95), (0.88, 0.05), (0.60, 0.50), (0.40, 0.50)]),
        rocks: pts([(0.05, 0.55), (0.95, 0.45), (0.50, 0.95)]),
        pond: CGPoint(x: 0.88, y: 0.02),
        curvy: false,
        extraTrees: 8,
        boulders: pts([(0.12, 0.42), (0.88, 0.58), (0.15, 0.10), (0.85, 0.92)]),
        theme: .volcano
    )

    static let all: [MapDefinition] = [switchback, meadowRun, crossroads, bullseye, threeRivers, gauntlet]
}
