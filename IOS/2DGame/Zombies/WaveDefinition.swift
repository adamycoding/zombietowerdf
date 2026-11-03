//
//  WaveDefinition.swift
//  2DGame
//
//  Created by Adam Yang on 10/19/26.
//

import Foundation

enum ZombieType: String, Decodable {
    case normal
    case runner
    case armored
    case tank

    var stats: ZombieStats {
        switch self {
        case .normal:
            return ZombieStats.normal
        case .runner:
            return ZombieStats.runner
        case .armored:
            return ZombieStats.armored
        case .tank:
            return ZombieStats.tank
        }
    }
}

// One group of a particular enemy type.
struct ZombieGroup: Decodable {
    let type: ZombieType
    let count: Int
}

struct RoundConfiguration: Decodable {
    let rounds: [WaveDefinition]
}

struct WaveDefinition: Decodable {
    let name: String
    let zombieTypes: [ZombieType]
    let spawnInterval: TimeInterval

    var zombieCount: Int {
        zombieTypes.count
    }

    init(zombieTypes: [ZombieType], spawnInterval: TimeInterval) {
        self.name = ""
        self.zombieTypes = zombieTypes
        self.spawnInterval = spawnInterval
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case count
        case groups
        case spawnInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)

        let interval = try container.decode(
            TimeInterval.self,
            forKey: .spawnInterval
        )

        guard interval.isFinite, interval > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .spawnInterval,
                in: container,
                debugDescription: "Spawn interval must be greater than zero."
            )
        }

        let groups: [ZombieGroup]

        if container.contains(.groups) {
            groups = try container.decode(
                [ZombieGroup].self,
                forKey: .groups
            )
        } else {
            // Still supports your current count-only JSON.
            let count = try container.decode(Int.self, forKey: .count)
            groups = [ZombieGroup(type: .normal, count: count)]
        }

        guard !groups.isEmpty,
              groups.allSatisfy({ $0.count > 0 && $0.count <= 1000 })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .groups,
                in: container,
                debugDescription: "Each group needs between 1 and 1000 zombies."
            )
        }

        guard groups.count <= 1000,
              groups.reduce(0, { $0 + $1.count }) <= 1000
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .groups,
                in: container,
                debugDescription: "A round cannot exceed 1000 zombies."
            )
        }

        zombieTypes = groups.flatMap { group in
            Array(repeating: group.type, count: group.count)
        }

        spawnInterval = interval
    }
}
