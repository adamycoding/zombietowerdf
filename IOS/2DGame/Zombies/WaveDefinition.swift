//
//  WaveDefinition.swift
//  2DGame
//
//  Created by Adam Yang on 10/19/26.
//

import Foundation

enum ZombieType {
    case normal
}

// this defines how many zmobies per wave and also spawning intervals (how fast they spawn).
struct WaveDefinition {
    let zombieTypes: [ZombieType]
    let spawnInterval: TimeInterval

    var zombieCount: Int {
        zombieTypes.count
    }
}
