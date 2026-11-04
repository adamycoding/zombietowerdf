//
//  Layer.swift
//  Core
//
//  Z-order for everything drawn in the world, so towers, zombies and UI
//  never fight over who is on top.
//

import SpriteKit

enum Layer: CGFloat {
    case background = 0
    case path = 10
    case towers = 20
    case zombies = 30
    case projectiles = 40
    case effects = 50
    case hud = 100
}
