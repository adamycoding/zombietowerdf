//
//  TowerAppearance.swift
//  Towers
//
//  How towers look: their color, icon and range ring. The panel, the drag
//  preview and placed towers all share these.
//

import SpriteKit
import UIKit

extension TowerType {
    var color: UIColor {
        switch self {
        case .soldier: return .systemGreen
        case .sniper: return .systemOrange
        case .ice: return .systemCyan
        }
    }

    func makeIcon(enabled: Bool) -> SKSpriteNode {
        let tint: UIColor = enabled ? color : .lightGray
        let image = UIImage(systemName: symbolName)?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        let icon: SKSpriteNode
        if let image {
            icon = SKSpriteNode(texture: SKTexture(image: image))
        } else {
            icon = SKSpriteNode(color: tint, size: CGSize(width: 24, height: 24))
        }
        icon.size = CGSize(width: 24, height: 24)
        icon.zPosition = 1
        return icon
    }
}

enum TowerVisuals {
    /// Soft filled circle showing a tower's shooting range. Shown while a
    /// tower is being dragged and while a placed tower is selected.
    static func makeRangeRing(radius: CGFloat) -> SKShapeNode {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.name = "rangeRing"
        ring.fillColor = UIColor.white.withAlphaComponent(0.08)
        ring.strokeColor = UIColor.white.withAlphaComponent(0.55)
        ring.lineWidth = 1.5
        ring.zPosition = -1 // behind the tower icon and its outline
        return ring
    }
}
