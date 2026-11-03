//
//  ZombieStats.swift
//  2DGame
//
//  Created by Adam Yang on 11/3/26.
//

import Foundation

struct ZombieStats {
    let health: Int
    let speed: Double
    let reward: Int

    static let normal = ZombieStats(
        health: 3,
        speed: 60,
        reward: 10
    )

    static let runner = ZombieStats(
        health: 2,
        speed: 95,
        reward: 10
    )

    static let armored = ZombieStats(
        health: 8,
        speed: 45,
        reward: 20
    )

    static let tank = ZombieStats(
        health: 18,
        speed: 28,
        reward: 30
    )
}
