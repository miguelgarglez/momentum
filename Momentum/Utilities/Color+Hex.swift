//
//  Color+Hex.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftUI

extension Color {
    nonisolated init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") {
            string.removeFirst()
        }

        guard string.count == 6,
              let value = UInt64(string, radix: 16) else { return nil }

        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
