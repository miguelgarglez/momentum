//
//  Color+Hex.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

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

    nonisolated func hexString() -> String? {
#if os(macOS)
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else { return nil }
        let red = Int(round(rgb.redComponent * 255.0))
        let green = Int(round(rgb.greenComponent * 255.0))
        let blue = Int(round(rgb.blueComponent * 255.0))
        return String(format: "#%02X%02X%02X", red, green, blue)
#else
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int(round(red * 255.0)), Int(round(green * 255.0)), Int(round(blue * 255.0)))
#endif
    }
}
