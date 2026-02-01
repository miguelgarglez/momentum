//
//  ProjectIconGlyph.swift
//  Momentum
//
//  Created by Codex on 01/02/26.
//

import SwiftUI

struct ProjectIconGlyph: View {
    let name: String
    let size: CGFloat
    let weight: Font.Weight
    let symbolStyle: AnyShapeStyle?
    let emojiStyle: Font?

    init(
        name: String,
        size: CGFloat,
        weight: Font.Weight = .semibold,
        symbolStyle: AnyShapeStyle? = nil,
        emojiStyle: Font? = nil
    ) {
        self.name = name
        self.size = size
        self.weight = weight
        self.symbolStyle = symbolStyle
        self.emojiStyle = emojiStyle
    }

    var body: some View {
        if EmojiDetector.isEmoji(name) {
            Text(name)
                .font(emojiStyle ?? .system(size: size))
        } else {
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(symbolStyle ?? AnyShapeStyle(.primary))
        }
    }
}
