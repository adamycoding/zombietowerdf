//
//  OutlinedLabel.swift
//  Core
//
//  A label with a thin black outline so it stays readable on any map colour.
//  (SpriteKit labels have no stroke, so black copies sit 1pt around the text.)
//

import SpriteKit
import UIKit

final class OutlinedLabel: SKLabelNode {

    private var copies: [SKLabelNode] = []
    private static let offsets: [CGPoint] = [
        CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1),
        CGPoint(x: -0.8, y: -0.8), CGPoint(x: 0.8, y: -0.8), CGPoint(x: -0.8, y: 0.8), CGPoint(x: 0.8, y: 0.8)
    ]

    override var text: String? { didSet { sync() } }
    override var fontSize: CGFloat { didSet { sync() } }
    override var fontName: String? { didSet { sync() } }
    override var horizontalAlignmentMode: SKLabelHorizontalAlignmentMode { didSet { sync() } }
    override var verticalAlignmentMode: SKLabelVerticalAlignmentMode { didSet { sync() } }

    private func sync() {
        if copies.isEmpty {
            for offset in OutlinedLabel.offsets {
                let copy = SKLabelNode()
                copy.fontColor = .black
                copy.position = offset
                copy.zPosition = -1
                addChild(copy)
                copies.append(copy)
            }
        }
        for copy in copies {
            copy.fontName = fontName
            copy.fontSize = fontSize
            copy.text = text
            copy.horizontalAlignmentMode = horizontalAlignmentMode
            copy.verticalAlignmentMode = verticalAlignmentMode
        }
    }
}
