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
        // Transparent parent holding the tower's visible parts.
        let icon = SKSpriteNode(
            color: .clear,
            size: CGSize(width: 24, height: 24)
        )
        icon.alpha = enabled ? 1 : 0.45
        icon.zPosition = 1

        let outline = UIColor(
            red: 0.13, green: 0.16, blue: 0.13, alpha: 1
        )
        let metal = UIColor(
            red: 0.38, green: 0.50, blue: 0.53, alpha: 1
        )
        let wood = UIColor(
            red: 0.48, green: 0.34, blue: 0.19, alpha: 1
        )

        // Each new piece is drawn over the previous pieces.
        var nextLayer: CGFloat = 0

        func addPiece(
            width: CGFloat,
            height: CGFloat,
            x: CGFloat,
            y: CGFloat,
            color: UIColor
        ) {
            let piece = SKShapeNode(
                rectOf: CGSize(width: width, height: height),
                cornerRadius: 2
            )
            piece.position = CGPoint(x: x, y: y)
            piece.fillColor = color
            piece.strokeColor = outline
            piece.lineWidth = 1.5
            piece.zPosition = nextLayer
            nextLayer += 1
            icon.addChild(piece)
        }

        switch self {
        case .soldier:
            // Platform and support.
            addPiece(
                width: 24, height: 7,
                x: 0, y: -10, color: .darkGray
            )
            addPiece(
                width: 8, height: 12,
                x: 0, y: -3, color: .gray
            )

            // Turret housing and barrel.
            addPiece(
                width: 22, height: 13,
                x: -2, y: 5, color: metal
            )
            addPiece(
                width: 13, height: 6,
                x: 10, y: 6, color: .darkGray
            )
            addPiece(
                width: 4, height: 8,
                x: 16, y: 6, color: .gray
            )

            // Highlight on the housing.
            addPiece(
                width: 5, height: 3,
                x: -6, y: 7, color: .lightGray
            )

        case .sniper:
            // Wooden platform and supports.
            addPiece(
                width: 25, height: 7,
                x: 0, y: -10, color: wood
            )
            for x: CGFloat in [-6, 6] {
                addPiece(
                    width: 5, height: 18,
                    x: x, y: 0, color: wood
                )
            }

            // Rifle stock, long barrel, and scope.
            addPiece(
                width: 14, height: 7,
                x: -6, y: 7, color: wood
            )
            addPiece(
                width: 28, height: 4,
                x: 3, y: 10, color: .gray
            )
            addPiece(
                width: 10, height: 4,
                x: 0, y: 15, color: .darkGray
            )

        case .ice:
            // Frozen platform.
            addPiece(
                width: 25, height: 7,
                x: 0, y: -10, color: metal
            )

            // Three pointed ice crystals.
            for x: CGFloat in [-8, 0, 8] {
                let tip: CGFloat = x == 0 ? 20 : 11

                let crystalPath = CGMutablePath()
                crystalPath.move(to: CGPoint(x: x - 4, y: -8))
                crystalPath.addLine(to: CGPoint(x: x - 5, y: tip - 6))
                crystalPath.addLine(to: CGPoint(x: x, y: tip))
                crystalPath.addLine(to: CGPoint(x: x + 5, y: tip - 6))
                crystalPath.addLine(to: CGPoint(x: x + 4, y: -8))
                crystalPath.closeSubpath()

                let crystal = SKShapeNode(path: crystalPath)
                crystal.fillColor = UIColor(
                    red: 0.49, green: 0.84, blue: 0.94, alpha: 1
                )
                crystal.strokeColor = outline
                crystal.lineWidth = 1.5
                crystal.zPosition = nextLayer
                nextLayer += 1
                icon.addChild(crystal)
            }
        }

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
