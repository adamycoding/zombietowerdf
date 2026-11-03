//
//  MapPreview.swift
//  Map
//
//  A picture of a map for the map-select cards. It draws the real map with the
//  same code the game uses (roads, scenery, pond, house), so the card looks
//  exactly like the level, then bakes it into one texture.
//

import SpriteKit
import UIKit

enum MapPreview {

    /// A typical play area (the part of the screen left of the tower panel).
    static let size = CGSize(width: 640, height: 340)

    private static var cache: [String: SKTexture] = [:]

    static func texture(for map: MapDefinition) -> SKTexture? {
        if let cached = cache[map.name] { return cached }

        let root = SKNode()
        let ground = SKSpriteNode(color: map.theme.ground, size: size)
        ground.anchorPoint = .zero
        ground.zPosition = -1
        root.addChild(ground)

        // The game keeps the road 40/60 points inside the play area; match that.
        let bounds = GamePath.Bounds(left: 40, right: size.width - 40, bottom: 60, top: size.height - 60)
        let path = GamePath(world: root, map: map)
        path.rebuild(in: bounds)

        let texture = SKView().texture(from: root, crop: CGRect(origin: .zero, size: size))
        if let texture { cache[map.name] = texture }
        return texture
    }
}
