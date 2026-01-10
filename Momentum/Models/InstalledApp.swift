//
//  InstalledApp.swift
//  Momentum
//
//  Created by Codex on 24/11/25.
//

import AppKit
import Foundation
import SwiftUI

struct InstalledApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    let url: URL
    private let iconImage: NSImage?

    init(bundleIdentifier: String, name: String, url: URL, icon: NSImage?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.url = url
        iconImage = icon
    }

    var id: String { bundleIdentifier }

    var icon: Image {
        if let iconImage {
            return Image(nsImage: iconImage)
        }
        return Image(systemName: "app")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}
