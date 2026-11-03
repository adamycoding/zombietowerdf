//
//  GamePath.swift
//  Map
//
//  The route zombies walk, plus drawing it and measuring distance to it.
//  When maps arrive (MH2D map tasks), a map loader can fill `waypoints`
//  from data instead of `rebuild` computing a fixed shape.
//

import SpriteKit
import UIKit

final class GamePath {
    /// Drawn width of the road.
    static let width: CGFloat = 32
    static var halfWidth: CGFloat { width / 2 }

    /// Where the route may be drawn (already inside the safe area / above the panel).
    struct Bounds {
        var left: CGFloat
        var right: CGFloat
        var bottom: CGFloat
        var top: CGFloat
    }

    /// Every route zombies can take (one entry per lane).
    private(set) var lanes: [[CGPoint]] = []
    /// The first lane (kept for code that only cares about one route).
    var waypoints: [CGPoint] { lanes.first ?? [] }
    let map: MapDefinition
    private let world: SKNode

    init(world: SKNode, map: MapDefinition = .meadowRun) {
        self.world = world
        self.map = map
    }

    var isEmpty: Bool { lanes.isEmpty }

    /// Rounds the corners: a smooth curve through the points (Catmull-Rom),
    /// sampled into short straight pieces. The same number of pieces every
    /// time, so zombies can keep their place when the map is resized.
    private static func smooth(_ pts: [CGPoint], steps: Int = 10) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out: [CGPoint] = [pts[0]]
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                let t2 = t * t, t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                out.append(CGPoint(x: x, y: y))
            }
        }
        return out
    }

    // MARK: Obstacles (they block towers' shots)

    struct Obstacle {
        let center: CGPoint
        let radius: CGFloat
    }
    private(set) var obstacles: [Obstacle] = []

    /// True if something stands between the two points (a shot from `a`
    /// to `b` would hit it). Things the tower itself is touching don't count.
    func isBlocked(from a: CGPoint, to b: CGPoint) -> Bool {
        let abx = b.x - a.x, aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return false }
        for o in obstacles {
            if hypot(o.center.x - a.x, o.center.y - a.y) <= o.radius { continue }
            if hypot(o.center.x - b.x, o.center.y - b.y) <= o.radius { continue } // zombie right beside it
            let t = max(0, min(1, ((o.center.x - a.x) * abx + (o.center.y - a.y) * aby) / lengthSquared))
            let closest = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
            if hypot(closest.x - o.center.x, closest.y - o.center.y) < o.radius { return true }
        }
        return false
    }

    /// Cuts each straight piece of a lane (in 0...1 map space) into shorter ones.
    private static func subdivided(_ pts: [CGPoint], pieceLength: CGFloat) -> [CGPoint] {
        guard let first = pts.first else { return pts }
        var out = [first]
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let count = max(1, Int((hypot(b.x - a.x, b.y - a.y) / pieceLength).rounded(.up)))
            for k in 1...count {
                let t = CGFloat(k) / CGFloat(count)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out
    }

    private static func shrunk(_ b: Bounds, to area: CGFloat) -> Bounds {
        let dx = (b.right - b.left) * (1 - area) / 2
        let dy = (b.top - b.bottom) * (1 - area) / 2
        return Bounds(left: b.left + dx, right: b.right - dx, bottom: b.bottom + dy, top: b.top - dy)
    }

    /// Builds the route for the given area and draws it. Returns the old
    /// waypoints if the route changed (so zombies can be moved onto the new
    /// route), or nil if nothing changed / the area is unusable.
    @discardableResult
    func rebuild(in bounds: Bounds) -> [[CGPoint]]? {
        guard bounds.right > bounds.left, bounds.top > bounds.bottom else { return nil }

        // Smaller maps only use the middle part of the play area.
        let route = GamePath.shrunk(bounds, to: map.area)
        let routeWidth = route.right - route.left
        let routeHeight = route.top - route.bottom
        let newLanes: [[CGPoint]] = map.lanes.map { lane in
            // Sharp-cornered roads are cut into short pieces (long single
            // strokes drew as skewed wedges where they run off the screen).
            // The count comes from the map data, not the screen size.
            var unit: [CGPoint] = lane
            if !map.curvy { unit = GamePath.subdivided(lane, pieceLength: 0.03) }
            var points = unit.map { CGPoint(x: route.left + routeWidth * $0.x, y: route.bottom + routeHeight * $0.y) }
            // Roads that start at an edge begin just off the screen, so
            // zombies walk in from outside instead of appearing on the map.
            if let first = lane.first, let start = points.first {
                var outside: CGPoint?
                if first.x <= 0.001 {
                    outside = CGPoint(x: -50, y: start.y)
                } else if first.y <= 0.001 {
                    outside = CGPoint(x: start.x, y: -50)
                } else if first.y >= 0.999 {
                    outside = CGPoint(x: start.x, y: bounds.top + 110)
                } else if first.x >= 0.999 {
                    // Right edge: the road runs in from behind the tower panel.
                    outside = CGPoint(x: start.x + 220, y: start.y)
                }
                if let outside {
                    // Several short pieces from outside the screen to the start.
                    // (Curvy roads get a single point: the smoothing cuts it up itself,
                    // and a crowd of close points makes the curve kink.)
                    let pieces = map.curvy ? 1 : 6
                    for k in (0..<pieces).reversed() {
                        let t = CGFloat(k) / CGFloat(pieces)
                        points.insert(CGPoint(x: outside.x + (start.x - outside.x) * t,
                                              y: outside.y + (start.y - outside.y) * t), at: 0)
                    }
                }
            }
            return map.curvy ? GamePath.smooth(points) : points
        }

        // refreshTowerPanel() asks for this on every tap/money change.
        // If the route hasn't moved, there is nothing to rebuild.
        if newLanes == lanes, world.childNode(withName: "zombiePath") != nil {
            return nil
        }

        let old = lanes
        lanes = newLanes
        drawGrass(in: bounds)
        drawScenery(in: bounds)
        drawPond(in: bounds)
        draw()
        return old
    }
    
    private func drawGrass(in bounds: Bounds) {
        // Replace the previous grass when the map layout changes.
        world.childNode(withName: "mapGrass")?.removeFromParent()

        let grassGroup = SKNode()
        grassGroup.name = "mapGrass"
        grassGroup.zPosition = Layer.background.rawValue + 1

        let width = bounds.right - bounds.left
        let height = bounds.top - bounds.bottom

        for index in 0..<100 {
            // Fixed positions keep the grass from shuffling around.
            let fractionX = CGFloat((index * 73 + 13) % 997) / 997
            let fractionY = CGFloat((index * 137 + 41) % 991) / 991

            let point = CGPoint(
                x: bounds.left + width * fractionX,
                y: bounds.bottom + height * fractionY
            )

            // Keep the road clear.
            guard distance(from: point) > GamePath.halfWidth + 8 else {
                continue
            }

            // Three short blades make one tuft.
            let blades = CGMutablePath()

            blades.move(to: CGPoint(x: -3, y: 0))
            blades.addLine(to: CGPoint(x: -5, y: 5))

            blades.move(to: .zero)
            blades.addLine(to: CGPoint(x: 0, y: 7))

            blades.move(to: CGPoint(x: 3, y: 0))
            blades.addLine(to: CGPoint(x: 5, y: 4))

            let tuft = SKShapeNode(path: blades)
            tuft.position = point
            tuft.strokeColor = map.theme.tuft
            tuft.lineWidth = 1.5
            tuft.lineCap = .round

            grassGroup.addChild(tuft)
        }

        world.addChild(grassGroup)
    }
    
    private func drawScenery(in bounds: Bounds) {
        world.childNode(withName: "mapScenery")?.removeFromParent()

        let scenery = SKNode()
        scenery.name = "mapScenery"
        scenery.zPosition = Layer.background.rawValue + 2

        let width = bounds.right - bounds.left
        let height = bounds.top - bounds.bottom

        func mapPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: bounds.left + width * x,
                y: bounds.bottom + height * y
            )
        }

        obstacles = []

        // Big rocks first, so the trees and small rocks keep clear of them.
        for spot in map.boulders {
            let point = mapPoint(spot.x, spot.y)
            guard distance(from: point) > GamePath.halfWidth + 22 + 8,
                  !touchesPond(point, radius: 22 + 6, in: bounds),
                  !obstacles.contains(where: { hypot($0.center.x - point.x, $0.center.y - point.y) < $0.radius + 22 + 6 }) else { continue }
            let boulder = makeBoulder()
            boulder.position = point
            scenery.addChild(boulder)
            obstacles.append(Obstacle(center: point, radius: 22))
        }

        // Positions expressed as fractions of the map size.
        var treePositions: [(CGFloat, CGFloat)] = map.trees.map { ($0.x, $0.y) }
        for i in 0..<map.extraTrees {
            treePositions.append((CGFloat((i * 47 + 19) % 97) / 97, CGFloat((i * 61 + 7) % 89) / 89))
        }

        for (x, y) in treePositions {
            let point = mapPoint(x, y)

            // Leave room beside the road.
            guard distance(from: point) > GamePath.halfWidth + 25,
                  !touchesPond(point, radius: 14, in: bounds),
                  !obstacles.contains(where: { hypot($0.center.x - point.x, $0.center.y - point.y) < $0.radius + 16 }) else {
                continue
            }

            let tree = makeTree()
            tree.position = point
            obstacles.append(Obstacle(center: point, radius: 12))
            scenery.addChild(tree)
        }

        let rockPositions: [(CGFloat, CGFloat)] = map.rocks.map { ($0.x, $0.y) }

        for (x, y) in rockPositions {
            let point = mapPoint(x, y)

            guard distance(from: point) > GamePath.halfWidth + 18,
                  !touchesPond(point, radius: 14, in: bounds),
                  !obstacles.contains(where: { hypot($0.center.x - point.x, $0.center.y - point.y) < $0.radius + 14 }) else {
                continue
            }
            obstacles.append(Obstacle(center: point, radius: 12))

            let rock = SKShapeNode(
                rectOf: CGSize(width: 25, height: 19),
                cornerRadius: 7
            )
            rock.position = point
            rock.zRotation = 0.25
            rock.fillColor = map.theme.rock
            rock.strokeColor = map.theme.rockEdge
            rock.lineWidth = 2
            scenery.addChild(rock)
        }

        world.addChild(scenery)
    }

    // MARK: Scenery pieces (they change with the map's theme)

    private func makeTree() -> SKNode {
        let theme = map.theme
        let tree = SKNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 36, height: 10))
        shadow.position.y = -8
        shadow.fillColor = SKColor.black.withAlphaComponent(0.18)
        shadow.strokeColor = .clear
        tree.addChild(shadow)
        let dark = SKColor(white: 0.1, alpha: 0.55)

        switch theme.tree {
        case .oak:
            let trunk = SKShapeNode(rectOf: CGSize(width: 8, height: 22), cornerRadius: 2)
            trunk.fillColor = theme.trunk
            trunk.strokeColor = .darkGray
            trunk.zPosition = 1
            tree.addChild(trunk)
            let leaves: [(CGFloat, CGFloat, CGFloat)] = [(-9, 10, 12), (9, 10, 12), (0, 22, 14), (0, 9, 14)]
            for (index, leaf) in leaves.enumerated() {
                let canopy = SKShapeNode(circleOfRadius: leaf.2)
                canopy.position = CGPoint(x: leaf.0, y: leaf.1)
                canopy.fillColor = theme.foliage
                canopy.strokeColor = dark
                canopy.lineWidth = 1.5
                canopy.zPosition = CGFloat(index + 2)
                tree.addChild(canopy)
            }
        case .pine:
            let trunk = SKShapeNode(rectOf: CGSize(width: 6, height: 12), cornerRadius: 1)
            trunk.position.y = -2
            trunk.fillColor = theme.trunk
            trunk.strokeColor = .darkGray
            tree.addChild(trunk)
            for (i, (w, y)) in [(30.0, 4.0), (24.0, 15.0), (17.0, 26.0)].enumerated() {
                let tier = CGMutablePath()
                tier.move(to: CGPoint(x: -w / 2, y: y))
                tier.addLine(to: CGPoint(x: w / 2, y: y))
                tier.addLine(to: CGPoint(x: 0, y: y + 16))
                tier.closeSubpath()
                let node = SKShapeNode(path: tier)
                node.fillColor = theme.foliage
                node.strokeColor = dark
                node.lineWidth = 1.5
                node.zPosition = CGFloat(i + 1)
                tree.addChild(node)
                if theme.snow {
                    let cap = CGMutablePath()
                    cap.move(to: CGPoint(x: -w * 0.22, y: y + 10))
                    cap.addLine(to: CGPoint(x: w * 0.22, y: y + 10))
                    cap.addLine(to: CGPoint(x: 0, y: y + 16))
                    cap.closeSubpath()
                    let snow = SKShapeNode(path: cap)
                    snow.fillColor = .white
                    snow.strokeColor = .clear
                    snow.zPosition = CGFloat(i + 1) + 0.5
                    tree.addChild(snow)
                }
            }
        case .cactus:
            func part(_ size: CGSize, _ x: CGFloat, _ y: CGFloat) {
                let n = SKShapeNode(rectOf: size, cornerRadius: min(size.width, size.height) / 2.2)
                n.position = CGPoint(x: x, y: y)
                n.fillColor = theme.foliage
                n.strokeColor = dark
                n.lineWidth = 1.5
                tree.addChild(n)
            }
            part(CGSize(width: 9, height: 12), -10, 12)   // left arm (up)
            part(CGSize(width: 12, height: 6), -6, 6)     // left arm (out)
            part(CGSize(width: 9, height: 10), 10, 16)    // right arm (up)
            part(CGSize(width: 12, height: 6), 6, 10)     // right arm (out)
            part(CGSize(width: 12, height: 32), 0, 10)    // trunk (on top)
        case .dead:
            let branches = CGMutablePath()
            branches.move(to: CGPoint(x: 0, y: -8))
            branches.addLine(to: CGPoint(x: 0, y: 16))
            branches.move(to: CGPoint(x: 0, y: 6))
            branches.addLine(to: CGPoint(x: -11, y: 18))
            branches.move(to: CGPoint(x: 0, y: 11))
            branches.addLine(to: CGPoint(x: 10, y: 22))
            branches.move(to: CGPoint(x: -6, y: 13))
            branches.addLine(to: CGPoint(x: -9, y: 24))
            let wood = SKShapeNode(path: branches)
            wood.strokeColor = theme.trunk
            wood.lineWidth = 4
            wood.lineCap = .round
            tree.addChild(wood)
            // A few leaves/embers hanging on.
            for (x, y) in [(-11.0, 18.0), (10.0, 22.0), (-9.0, 24.0)] {
                let dot = SKShapeNode(circleOfRadius: 3)
                dot.position = CGPoint(x: x, y: y)
                dot.fillColor = theme.foliage
                dot.strokeColor = .clear
                tree.addChild(dot)
            }
        }
        return tree
    }

    private func makeBoulder() -> SKNode {
        let theme = map.theme
        let boulder = SKNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 52, height: 14))
        shadow.position.y = -14
        shadow.fillColor = SKColor.black.withAlphaComponent(0.2)
        shadow.strokeColor = .clear
        boulder.addChild(shadow)

        let lumps: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, 0, 44, 34), (-12, 8, 24, 20), (13, 5, 22, 18)]
        for (i, l) in lumps.enumerated() {
            let lump = SKShapeNode(rectOf: CGSize(width: l.2, height: l.3), cornerRadius: 11)
            lump.position = CGPoint(x: l.0, y: l.1)
            lump.fillColor = theme.boulder
            lump.strokeColor = theme.rockEdge
            lump.lineWidth = 2
            lump.zPosition = CGFloat(i)
            boulder.addChild(lump)
        }
        // A highlight (a snow cap on snowy maps, a glowing crack on the volcano).
        let mark = SKShapeNode(rectOf: CGSize(width: 18, height: theme.snow ? 8 : 3), cornerRadius: 2)
        mark.position = CGPoint(x: -4, y: theme.snow ? 14 : 4)
        mark.fillColor = theme.snow ? .white : theme.roadEdge.withAlphaComponent(0.75)
        mark.strokeColor = .clear
        mark.zPosition = 5
        boulder.addChild(mark)
        return boulder
    }

    /// The pond's centre and size (used by drawPond and by scenery that must keep clear of it).
    private func pondShape(in bounds: Bounds) -> (center: CGPoint, width: CGFloat, height: CGFloat)? {
        guard let spot = map.pond else { return nil }
        let width = bounds.right - bounds.left
        let height = bounds.top - bounds.bottom
        return (CGPoint(x: bounds.left + width * spot.x, y: bounds.bottom + height * spot.y),
                min(CGFloat(90), width * 0.18), min(CGFloat(36), height * 0.28))
    }

    /// True if a circle of `radius` at `point` would overlap the pond.
    private func touchesPond(_ point: CGPoint, radius: CGFloat, in bounds: Bounds) -> Bool {
        guard let pond = pondShape(in: bounds) else { return false }
        // The pond's outline bulges a little past its nominal size, so allow for that.
        let rx = pond.width * 0.65 + radius, ry = pond.height * 0.9 + radius
        let nx = (point.x - pond.center.x) / rx, ny = (point.y - pond.center.y) / ry
        return nx * nx + ny * ny < 1
    }

    private func drawPond(in bounds: Bounds) {
        world.childNode(withName: "mapPond")?.removeFromParent()
        guard let spot = map.pond else { return }

        let width = bounds.right - bounds.left
        let height = bounds.top - bounds.bottom

        let pond = SKNode()
        pond.name = "mapPond"
        pond.position = CGPoint(
            x: bounds.left + width * spot.x,
            y: bounds.bottom + height * spot.y
        )
        // Not on top of a road.
        guard distance(from: pond.position) > GamePath.halfWidth + 40 else { return }
        pond.zPosition = Layer.background.rawValue + 3

        // Keep the pond small enough to fit below the road.
        let pondWidth = min(CGFloat(90), width * 0.18)
        let pondHeight = min(CGFloat(36), height * 0.28)

        // An uneven outline gives the pond a natural shape.
        let outline = CGMutablePath()
        outline.move(to: CGPoint(
            x: -pondWidth * 0.5,
            y: 0
        ))
        outline.addCurve(
            to: CGPoint(x: 0, y: pondHeight * 0.5),
            control1: CGPoint(
                x: -pondWidth * 0.55,
                y: pondHeight * 0.45
            ),
            control2: CGPoint(
                x: -pondWidth * 0.15,
                y: pondHeight * 0.35
            )
        )
        outline.addCurve(
            to: CGPoint(x: pondWidth * 0.5, y: 0),
            control1: CGPoint(
                x: pondWidth * 0.4,
                y: pondHeight * 0.7
            ),
            control2: CGPoint(
                x: pondWidth * 0.6,
                y: pondHeight * 0.25
            )
        )
        outline.addCurve(
            to: CGPoint(x: -pondWidth * 0.5, y: 0),
            control1: CGPoint(
                x: pondWidth * 0.4,
                y: -pondHeight * 0.7
            ),
            control2: CGPoint(
                x: -pondWidth * 0.4,
                y: -pondHeight * 0.6
            )
        )
        outline.closeSubpath()

        let water = SKShapeNode(path: outline)
        water.fillColor = map.theme.water
        water.strokeColor = map.theme.shore
        water.lineWidth = 5
        pond.addChild(water)

        // Pale lines suggest reflections on the water.
        for index in 0..<3 {
            let ripple = SKShapeNode(
                rectOf: CGSize(width: pondWidth * 0.18, height: 1),
                cornerRadius: 0.5
            )
            ripple.position = CGPoint(
                x: CGFloat(index - 1) * pondWidth * 0.25,
                y: index == 1 ? pondHeight * 0.15 : 0
            )
            ripple.fillColor = SKColor.white.withAlphaComponent(0.3)
            ripple.strokeColor = .clear
            ripple.zPosition = 1
            pond.addChild(ripple)
        }

        world.addChild(pond)
    }
    
    private func draw() {
        world.childNode(withName: "zombiePath")?.removeFromParent()
        world.enumerateChildNodes(withName: "baseHouse") { node, _ in node.removeFromParent() }

        // The roads are drawn once into a picture with Core Graphics (its line
        // drawing is reliable) and shown as one sprite. SpriteKit's own
        // stroked lines drew skewed wedges on long, many-pointed roads.
        let roads = SKNode()
        roads.name = "zombiePath"
        roads.zPosition = Layer.path.rawValue

        let points = lanes.flatMap { $0 }
        if let firstPoint = points.first {
            let box = points.reduce(CGRect(origin: firstPoint, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }.insetBy(dx: -30, dy: -30)
            let renderer = UIGraphicsImageRenderer(size: box.size)
            let image = renderer.image { context in
                let cg = context.cgContext
                // Flip to SpriteKit's y-up and shift so `box` starts at (0, 0).
                cg.translateBy(x: 0, y: box.height)
                cg.scaleBy(x: 1, y: -1)
                cg.translateBy(x: -box.minX, y: -box.minY)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                func strokeLanes(width: CGFloat, color: UIColor) {
                    cg.setStrokeColor(color.cgColor)
                    cg.setLineWidth(width)
                    for lane in lanes where lane.count >= 2 {
                        cg.beginPath()
                        cg.move(to: lane[0])
                        for point in lane.dropFirst() { cg.addLine(to: point) }
                        cg.strokePath()
                    }
                }
                // All edges first, then all roads, so crossing roads merge cleanly.
                strokeLanes(width: GamePath.width + 6, color: map.theme.roadEdge)
                strokeLanes(width: GamePath.width, color: map.theme.road)
            }
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            sprite.anchorPoint = .zero
            sprite.position = box.origin
            sprite.size = box.size
            roads.addChild(sprite)
        }
        addRoadDecay(to: roads)
        world.addChild(roads)

        // One house per distinct end point (lanes normally share it).
        var ends: [CGPoint] = []
        for lane in lanes {
            guard let end = lane.last else { continue }
            if !ends.contains(where: { hypot($0.x - end.x, $0.y - end.y) < 4 }) { ends.append(end) }
        }
        for end in ends { drawHouse(at: end) }
    }

    /// Cracks, potholes, rubble along the edges and a faded, broken centre line,
    /// so the roads look worn out and abandoned. Always the same pattern for
    /// a given map (fixed seed), and only four nodes however long the roads are.
    private func addRoadDecay(to roads: SKNode) {
        let cracks = CGMutablePath()
        let potholes = CGMutablePath()
        let rubble = CGMutablePath()
        let dashes = CGMutablePath()
        var seed: UInt64 = 987_654_321
        func rnd() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((seed >> 33) & 0xFFFFF) / CGFloat(0xFFFFF)
        }
        let hw = GamePath.halfWidth
        let spacing: CGFloat = 12

        for lane in lanes where lane.count >= 2 {
            var carried: CGFloat = 0
            for i in 1..<lane.count {
                let a = lane[i - 1], b = lane[i]
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0 else { continue }
                let dir = CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
                let normal = CGVector(dx: -dir.dy, dy: dir.dx)
                var d = carried
                while d < length {
                    let p = CGPoint(x: a.x + dir.dx * d, y: a.y + dir.dy * d)
                    let r = rnd()
                    if r < 0.30 {
                        // A jagged crack running roughly along the road.
                        let across = (rnd() * 2 - 1) * (hw - 4)
                        var c = CGPoint(x: p.x + normal.dx * across, y: p.y + normal.dy * across)
                        var angle = atan2(dir.dy, dir.dx) + (rnd() - 0.5) * 1.6
                        cracks.move(to: c)
                        for _ in 0..<3 {
                            let step = 3 + rnd() * 5
                            c = CGPoint(x: c.x + cos(angle) * step, y: c.y + sin(angle) * step)
                            cracks.addLine(to: c)
                            angle += (rnd() - 0.5) * 1.4
                        }
                    } else if r < 0.37 {
                        let across = (rnd() * 2 - 1) * (hw - 9)
                        let w = 6 + rnd() * 6, h = 4 + rnd() * 3
                        potholes.addEllipse(in: CGRect(x: p.x + normal.dx * across - w / 2,
                                                       y: p.y + normal.dy * across - h / 2, width: w, height: h))
                    }
                    // Chunks of broken road along the edges.
                    if rnd() < 0.4 {
                        let side: CGFloat = rnd() < 0.5 ? -1 : 1
                        let offset = side * (hw + (rnd() - 0.5) * 6)
                        let size = 2 + rnd() * 3
                        rubble.addRect(CGRect(x: p.x + normal.dx * offset - size / 2,
                                              y: p.y + normal.dy * offset - size / 2, width: size, height: size * 0.8))
                    }
                    // Faded centre line with big gaps.
                    if rnd() > 0.45 {
                        dashes.move(to: p)
                        dashes.addLine(to: CGPoint(x: p.x + dir.dx * 7, y: p.y + dir.dy * 7))
                    }
                    d += spacing
                }
                carried = d - length
            }
        }

        func add(_ path: CGPath, fill: SKColor?, stroke: SKColor?, width: CGFloat, z: CGFloat) {
            let node = SKShapeNode(path: path)
            node.fillColor = fill ?? .clear
            node.strokeColor = stroke ?? .clear
            node.lineWidth = width
            node.lineCap = .round
            node.zPosition = z
            roads.addChild(node)
        }
        add(dashes, fill: nil, stroke: SKColor(white: 1, alpha: 0.22), width: 2, z: 2)
        add(potholes, fill: SKColor(white: 0, alpha: 0.28), stroke: nil, width: 0, z: 3)
        add(cracks, fill: nil, stroke: SKColor(white: 0, alpha: 0.45), width: 1, z: 4)
        add(rubble, fill: map.theme.roadEdge, stroke: nil, width: 0, z: 5)
    }

    private func drawHouse(at point: CGPoint) {
        let house = SKNode()
        house.name = "baseHouse"
        house.position = point
        house.zPosition = Layer.path.rawValue + 1

        // Main concrete walls.
        let walls = SKShapeNode(
            rectOf: CGSize(width: 40, height: 34),
            cornerRadius: 2
        )
        walls.fillColor = SKColor(
            red: 0.58, green: 0.59, blue: 0.53, alpha: 1
        )
        walls.strokeColor = .darkGray
        walls.lineWidth = 2
        house.addChild(walls)

        // Sloped roof.
        let roofPath = CGMutablePath()
        roofPath.move(to: CGPoint(x: -24, y: 15))
        roofPath.addLine(to: CGPoint(x: -14, y: 29))
        roofPath.addLine(to: CGPoint(x: 14, y: 29))
        roofPath.addLine(to: CGPoint(x: 24, y: 15))
        roofPath.closeSubpath()

        let roof = SKShapeNode(path: roofPath)
        roof.fillColor = SKColor(
            red: 0.38, green: 0.40, blue: 0.36, alpha: 1
        )
        roof.strokeColor = .darkGray
        roof.lineWidth = 2
        house.addChild(roof)

        // Dark entrance.
        let door = SKShapeNode(
            rectOf: CGSize(width: 12, height: 21),
            cornerRadius: 1
        )
        door.position = CGPoint(x: 0, y: -6)
        door.fillColor = SKColor(white: 0.18, alpha: 1)
        door.strokeColor = .darkGray
        house.addChild(door)

        // Two small windows.
        for x: CGFloat in [-12, 12] {
            let window = SKShapeNode(
                rectOf: CGSize(width: 6, height: 7)
            )
            window.position = CGPoint(x: x, y: 6)
            window.fillColor = SKColor(
                red: 0.69, green: 0.77, blue: 0.72, alpha: 1
            )
            window.strokeColor = .darkGray
            house.addChild(window)
        }

        world.addChild(house)
    }

    /// Shortest distance from a point to the zombie route (all segments).
    func distance(from point: CGPoint) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for waypoints in lanes where waypoints.count >= 2 {
            for i in 1..<waypoints.count {
                let a = waypoints[i - 1]
                let b = waypoints[i]
                let abx = b.x - a.x
                let aby = b.y - a.y
                let lengthSquared = abx * abx + aby * aby
                var t: CGFloat = 0
                if lengthSquared > 0 {
                    t = max(0, min(1, ((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSquared))
                }
                let closest = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
                best = min(best, hypot(point.x - closest.x, point.y - closest.y))
            }
        }
        return best
    }
}
