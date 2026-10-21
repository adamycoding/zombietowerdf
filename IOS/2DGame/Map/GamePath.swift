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

        let middleX = (bounds.left + bounds.right) / 2
        let lowerY = bounds.bottom + (bounds.top - bounds.bottom) * 0.25
        let upperY = bounds.bottom + (bounds.top - bounds.bottom) * 0.75

        let newWaypoints = [
            CGPoint(x: bounds.left, y: lowerY),    // Start
            CGPoint(x: middleX, y: lowerY),        // Walk right
            CGPoint(x: middleX, y: upperY),        // Turn upward
            CGPoint(x: bounds.right, y: upperY)    // Walk right to the end
        ]

        // refreshTowerPanel() asks for this on every tap/money change.
        // If the route hasn't moved, there is nothing to rebuild.
        if newWaypoints == waypoints, world.childNode(withName: "zombiePath") != nil {
            return nil
        }

        let old = waypoints
        waypoints = newWaypoints
        draw()
        return old
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
        pathNode.strokeColor = .brown
        pathNode.lineWidth = GamePath.width
        pathNode.lineJoin = .round // smooth corners instead of clipped ones
        pathNode.lineCap = .round
        pathNode.zPosition = Layer.path.rawValue
        world.addChild(pathNode)
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
