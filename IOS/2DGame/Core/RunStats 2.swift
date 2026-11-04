//
//  RunStats.swift
//  Core
//
//  What the player did this run. The Game Over screen (MH2D-81) shows the
//  number of waves survived.
//

import Foundation

final class RunStats {

    private(set) var wavesSurvived = 0

    func recordWaveSurvived() { wavesSurvived += 1 }

    func reset() { wavesSurvived = 0 }
}
