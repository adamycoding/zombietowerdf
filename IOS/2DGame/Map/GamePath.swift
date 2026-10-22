//
//  GamePath.swift
//  Map
//
//  The route zombies walk, plus drawing it and measuring distance to it.
//  When maps arrive (MH2D map tasks), a map loader can fill `waypoints`
//  from data instead of `rebuild` computing a fixed shape.
//

import SpriteKit

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

    private(set) var waypoints: [CGPoint] = []
    private let world: SKNode

    init(world: SKNode) {
        self.world = world
    }

    var isEmpty: Bool { waypoints.isEmpty }

    /// Builds the route for the given area and draws it. Returns the old
    /// waypoints if the route changed (so zombies can be moved onto the new
    /// route), or nil if nothing changed / the area is unusable.
    @discardableResult
    func rebuild(in bounds: Bounds) -> [CGPoint]? {
        guard bounds.right > bounds.left, bounds.top > bounds.bottom else { return nil }

        let width = bounds.right - bounds.left
        let height = bounds.top - bounds.bottom

        let newWaypoints = [
            // Enter from the left.
            CGPoint(
                x: bounds.left,
                y: bounds.bottom + height * 0.40
            ),

            // Walk right toward the first turn.
            CGPoint(
                x: bounds.left + width * 0.24,
                y: bounds.bottom + height * 0.40
            ),

            // Turn upward.
            CGPoint(
                x: bounds.left + width * 0.24,
                y: bounds.bottom + height * 0.73
            ),

            // Walk across the raised section.
            CGPoint(
                x: bounds.left + width * 0.48,
                y: bounds.bottom + height * 0.73
            ),

            // Turn downward.
            CGPoint(
                x: bounds.left + width * 0.48,
                y: bounds.bottom + height * 0.32
            ),

            // Follow the final stretch to the future house.
            CGPoint(
                x: bounds.right,
                y: bounds.bottom + height * 0.32
            )
        ]

        // refreshTowerPanel() asks for this on every tap/money change.
        // If the route hasn't moved, there is nothing to rebuild.
        if newWaypoints == waypoints, world.childNode(withName: "zombiePath") != nil {
            return nil
        }

        let old = waypoints
        waypoints = newWaypoints
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
            tuft.strokeColor = SKColor(
                red: 0.28, green: 0.39, blue: 0.19, alpha: 0.65
            )
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

        // Positions expressed as fractions of the map size.
        let treePositions: [(CGFloat, CGFloat)] = [
            (0.08, 0.08),
            (0.12, 0.88),
            (0.59, 0.88),
            (0.88, 0.88),
            (0.42, 0.04)
        ]

        for (x, y) in treePositions {
            let point = mapPoint(x, y)

            // Leave room beside the road.
            guard distance(from: point) > GamePath.halfWidth + 25 else {
                continue
            }

            let tree = SKNode()
            tree.position = point

            let shadow = SKShapeNode(
                ellipseOf: CGSize(width: 36, height: 10)
            )
            shadow.position.y = -8
            shadow.fillColor = SKColor.black.withAlphaComponent(0.18)
            shadow.strokeColor = .clear
            tree.addChild(shadow)

            let trunk = SKShapeNode(
                rectOf: CGSize(width: 8, height: 22),
                cornerRadius: 2
            )
            trunk.fillColor = SKColor(
                red: 0.39, green: 0.28, blue: 0.17, alpha: 1
            )
            trunk.strokeColor = .darkGray
            trunk.zPosition = 1
            tree.addChild(trunk)

            // Overlapping circles form a leafy canopy.
            let leaves: [(CGFloat, CGFloat, CGFloat)] = [
                (-9, 10, 12),
                (9, 10, 12),
                (0, 22, 14),
                (0, 9, 14)
            ]

            for (index, leaf) in leaves.enumerated() {
                let canopy = SKShapeNode(circleOfRadius: leaf.2)
                canopy.position = CGPoint(x: leaf.0, y: leaf.1)
                canopy.fillColor = SKColor(
                    red: 0.34,
                    green: 0.49,
                    blue: 0.24,
                    alpha: 1
                )
                canopy.strokeColor = SKColor(
                    red: 0.20,
                    green: 0.29,
                    blue: 0.14,
                    alpha: 1
                )
                canopy.lineWidth = 1.5
                canopy.zPosition = CGFloat(index + 2)
                tree.addChild(canopy)
            }

            scenery.addChild(tree)
        }

        let rockPositions: [(CGFloat, CGFloat)] = [
            (0.27, 0.05),
            (0.74, 0.86),
            (0.95, 0.08)
        ]

        for (x, y) in rockPositions {
            let point = mapPoint(x, y)

            guard distance(from: point) > GamePath.halfWidth + 18 else {
                continue
            }

            let rock = SKShapeNode(
                rectOf: CGSize(width: 25, height: 19),
                cornerRadius: 7
            )
            rock.position = point
            rock.zRotation = 0.25
            rock.fillColor = SKColor(
                red: 0.49, green: 0.51, blue: 0.44, alpha: 1
            )
            rock.strokeColor = SKColor(
                red: 0.28, green: 0.31, blue: 0.25, alpha: 1
            )
            rock.lineWidth = 2
            scenery.addChild(rock)
        }

        world.addChild(scenery)
    }

    private func drawPond(in bounds: Bounds) {
        world.childNode(withName: "mapPond")?.removeFromParent()

        let width = bounds.right - bounds.left
        let height = bounds.top - bounds.bottom

        let pond = SKNode()
        pond.name = "mapPond"
        pond.position = CGPoint(
            x: bounds.left + width * 0.77,
            y: bounds.bottom
        )
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
        water.fillColor = SKColor(
            red: 0.30, green: 0.53, blue: 0.57, alpha: 1
        )
        water.strokeColor = SKColor(
            red: 0.49, green: 0.62, blue: 0.39, alpha: 1
        )
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

        let drawing = CGMutablePath()
        drawing.move(to: waypoints[0])
        for waypoint in waypoints.dropFirst() {
            drawing.addLine(to: waypoint)
        }

        let pathNode = SKShapeNode(path: drawing)
        pathNode.name = "zombiePath"
        pathNode.strokeColor = SKColor(
            red: 0.77,
            green: 0.70,
            blue: 0.46,
            alpha: 1
        )
        pathNode.lineWidth = GamePath.width
        pathNode.lineJoin = .round // smooth corners instead of clipped ones
        pathNode.lineCap = .round
        pathNode.zPosition = Layer.path.rawValue
        world.addChild(pathNode)
        if let endPoint = waypoints.last {
            drawHouse(at: endPoint)
        }
    }
    
    private func drawHouse(at point: CGPoint) {
        // Remove the previous house if the map is resized.
        world.childNode(withName: "baseHouse")?.removeFromParent()

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
        guard waypoints.count >= 2 else { return .greatestFiniteMagnitude }
        var best = CGFloat.greatestFiniteMagnitude
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
        return best
    }
}
