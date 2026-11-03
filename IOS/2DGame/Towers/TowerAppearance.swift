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
        case .gunner: return .systemPurple
        case .sniper: return .systemOrange
        case .grenadier: return .systemRed
        case .flamethrower: return .systemPink
        case .tesla: return .systemIndigo
        case .trapper: return .systemBrown
        case .ice: return .systemCyan
        }
    }

    /// Towers whose gun points sideways swing around to face their target.
    /// (The Tesla, Barbed Wire and Ice towers don't have a gun that points
    /// anywhere in particular, so they stay put.)
    var turnsToAim: Bool {
        switch self {
        case .soldier, .gunner, .sniper, .grenadier, .flamethrower: return true
        case .tesla, .trapper, .ice: return false
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

        // The base stays put. Everything that should move (the gun, the
        // survivor, the coil) is added to `top`, which turns and animates.
        let top = SKNode()
        top.name = "towerTop"
        top.zPosition = 100
        icon.addChild(top)
        var current: SKNode = icon // where new pieces go: the base first, then `top`

        func addPiece(
            width: CGFloat,
            height: CGFloat,
            x: CGFloat,
            y: CGFloat,
            color: UIColor,
            line: CGFloat = 1.5
        ) {
            let piece = SKShapeNode(
                rectOf: CGSize(width: width, height: height),
                cornerRadius: 2
            )
            piece.position = CGPoint(x: x, y: y)
            piece.fillColor = color
            piece.strokeColor = outline
            piece.lineWidth = line
            piece.zPosition = nextLayer
            nextLayer += 1
            current.addChild(piece)
        }

        let sandbag = UIColor(
            red: 0.76, green: 0.67, blue: 0.47, alpha: 1
        )

        // A little survivor: boots, legs, jacket, arms, a round head with a
        // face, and a hat or bandana. (x, y) is the middle of the jacket.
        func addSurvivor(
            x: CGFloat,
            y: CGFloat,
            shirt: UIColor = UIColor(red: 0.35, green: 0.42, blue: 0.27, alpha: 1),
            hat: UIColor = UIColor(red: 0.30, green: 0.18, blue: 0.09, alpha: 1)
        ) {
            let skin = UIColor(red: 0.90, green: 0.73, blue: 0.58, alpha: 1)
            let jeans = UIColor(red: 0.22, green: 0.27, blue: 0.40, alpha: 1)
            let boots = UIColor(red: 0.20, green: 0.14, blue: 0.10, alpha: 1)

            // Legs and boots.
            for dx: CGFloat in [-2, 2] {
                addPiece(width: 3, height: 5, x: x + dx, y: y - 6, color: jeans, line: 1)
                addPiece(width: 4, height: 2, x: x + dx, y: y - 9, color: boots, line: 1)
            }
            // Jacket, with a lighter stripe down the middle.
            addPiece(width: 9, height: 9, x: x, y: y, color: shirt, line: 1)
            addPiece(width: 2, height: 8, x: x, y: y, color: UIColor(white: 1, alpha: 0.25), line: 0)
            // Arms with hands.
            for dx: CGFloat in [-6, 6] {
                addPiece(width: 3, height: 7, x: x + dx, y: y, color: shirt, line: 1)
                addPiece(width: 3, height: 2, x: x + dx, y: y - 4, color: skin, line: 1)
            }
            // Round head with two eyes.
            let head = SKShapeNode(circleOfRadius: 4)
            head.position = CGPoint(x: x, y: y + 9)
            head.fillColor = skin
            head.strokeColor = outline
            head.lineWidth = 1
            head.zPosition = nextLayer
            nextLayer += 1
            current.addChild(head)
            for dx: CGFloat in [-1.5, 1.5] {
                let eye = SKShapeNode(circleOfRadius: 0.6)
                eye.position = CGPoint(x: x + dx, y: y + 9.5)
                eye.fillColor = outline
                eye.strokeColor = .clear
                eye.zPosition = nextLayer
                nextLayer += 1
                current.addChild(eye)
            }
            // Hat / bandana over the top of the head.
            addPiece(width: 8, height: 3, x: x, y: y + 12, color: hat, line: 1)
            addPiece(width: 4, height: 1.5, x: x + 3, y: y + 10.5, color: hat, line: 0)
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

            current = top

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

        case .gunner:
            // Survivor behind a machine gun, on a sandbag wall.
            addPiece(
                width: 26, height: 8,
                x: 0, y: -10, color: sandbag
            )
            addPiece(
                width: 10, height: 4,
                x: -9, y: -4, color: sandbag
            )
            current = top
            addSurvivor(x: -7, y: 2,
                        shirt: UIColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 1), hat: .systemRed)
            // The machine gun sits on the sandbags and swings around to aim;
            // the gunner stays crouched behind it.
            let gun = SKNode()
            gun.name = "towerGun"
            gun.position = CGPoint(x: 3, y: 2)
            gun.zPosition = 50
            top.addChild(gun)
            current = gun
            addPiece(
                width: 12, height: 6,
                x: 2, y: 0, color: .darkGray
            )
            addPiece(
                width: 14, height: 3,
                x: 12, y: 1, color: .gray
            )
            addPiece(
                width: 6, height: 6,
                x: 1, y: -5, color: .systemYellow
            )

        case .sniper:
            // Wooden watchtower (the base): legs, a cross brace and a platform.
            for x: CGFloat in [-7, 7] {
                addPiece(
                    width: 3, height: 18,
                    x: x, y: -3, color: wood
                )
            }
            addPiece(
                width: 17, height: 2,
                x: 0, y: -4, color: wood
            )
            addPiece(
                width: 26, height: 4,
                x: 0, y: 6, color: wood
            )
            // A survivor standing upright on the platform. He doesn't turn.
            current = top
            addSurvivor(
                x: 0, y: 17,
                shirt: UIColor(red: 0.25, green: 0.38, blue: 0.25, alpha: 1),
                hat: UIColor(red: 0.70, green: 0.62, blue: 0.40, alpha: 1)
            )
            // Only the rifle swings around to aim. It pivots at his hands.
            let gun = SKNode()
            gun.name = "towerGun"
            gun.position = CGPoint(x: 0, y: 17)
            gun.zPosition = 50
            top.addChild(gun)
            current = gun
            addPiece(
                width: 24, height: 3,
                x: 11, y: 0, color: .gray
            )
            addPiece(
                width: 7, height: 3,
                x: 6, y: 3, color: .darkGray
            )
            addPiece(
                width: 8, height: 4,
                x: -1, y: -1, color: wood
            )

        case .grenadier:
            // Heavy base, fat mortar tube, and a shell in the muzzle.
            addPiece(
                width: 25, height: 7,
                x: 0, y: -10, color: .darkGray
            )
            current = top
            // A loader stands next to the mortar (he doesn't move).
            addSurvivor(
                x: -9, y: -1,
                shirt: UIColor(red: 0.55, green: 0.25, blue: 0.20, alpha: 1),
                hat: UIColor(white: 0.45, alpha: 1)
            )
            // The mortar tube leans left or right toward its target.
            let gun = SKNode()
            gun.name = "towerGun"
            gun.position = CGPoint(x: 6, y: -6)
            gun.zPosition = 50
            top.addChild(gun)
            current = gun
            addPiece(
                width: 12, height: 17,
                x: 0, y: 8.5,
                color: UIColor(red: 0.33, green: 0.42, blue: 0.22, alpha: 1)
            )
            addPiece(
                width: 16, height: 4,
                x: 0, y: 17, color: .gray
            )
            addPiece(
                width: 7, height: 7,
                x: 0, y: 21, color: .systemOrange
            )

        case .flamethrower:
            // Survivor with a fuel tank on his back and a flame nozzle.
            addPiece(
                width: 25, height: 7,
                x: 0, y: -10, color: .darkGray
            )
            current = top
            // Fuel tank on his back.
            addPiece(
                width: 6, height: 13,
                x: -12, y: 1, color: .systemRed
            )
            addSurvivor(
                x: -4, y: 0,
                shirt: UIColor(red: 0.60, green: 0.35, blue: 0.15, alpha: 1), hat: .gray
            )
            // Only the hose and nozzle swing around to aim.
            let gun = SKNode()
            gun.name = "towerGun"
            gun.position = CGPoint(x: 2, y: 2)
            gun.zPosition = 50
            top.addChild(gun)
            current = gun
            addPiece(
                width: 11, height: 3,
                x: 6, y: 0, color: .gray
            )
            addPiece(
                width: 6, height: 6,
                x: 13, y: 1, color: UIColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 1)
            )
            addPiece(
                width: 3, height: 3,
                x: 14, y: 1, color: .systemYellow
            )

        case .tesla:
            // Survivor-built tesla coil: copper rings and a glowing top.
            addPiece(
                width: 25, height: 7,
                x: 0, y: -10, color: metal
            )
            current = top
            addPiece(
                width: 5, height: 18,
                x: 5, y: 0, color: .darkGray
            )
            for y: CGFloat in [-4, 2] {
                addPiece(
                    width: 13, height: 3,
                    x: 5, y: y,
                    color: UIColor(red: 0.80, green: 0.50, blue: 0.25, alpha: 1)
                )
            }
            addPiece(
                width: 10, height: 10,
                x: 5, y: 13,
                color: UIColor(red: 0.72, green: 0.62, blue: 1.0, alpha: 1)
            )
            addSurvivor(x: -9, y: -3,
                        shirt: UIColor(white: 0.9, alpha: 1), hat: .systemIndigo)

        case .trapper:
            // Survivor holding a roll of barbed wire.
            addPiece(
                width: 25, height: 7,
                x: 0, y: -10, color: wood
            )
            current = top
            addSurvivor(x: -6, y: -1,
                        shirt: UIColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1),
                        hat: UIColor(red: 0.40, green: 0.25, blue: 0.12, alpha: 1))
            addPiece(
                width: 13, height: 13,
                x: 8, y: -1, color: .gray
            )
            addPiece(
                width: 7, height: 7,
                x: 8, y: -1, color: .darkGray
            )

        case .ice:
            // Frozen platform.
            addPiece(
                width: 25, height: 7,
                x: 0, y: -10, color: metal
            )

            current = top

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
                current.addChild(crystal)
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
