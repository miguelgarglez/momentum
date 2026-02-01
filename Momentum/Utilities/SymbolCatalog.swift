import Foundation

enum SymbolCatalog {
    private static let systemSymbolListPath =
        "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist"
    private static let systemSymbolCategoriesPath =
        "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_categories.plist"

    struct SymbolCategory: Identifiable {
        let id: String
        let title: String
        let symbols: [String]
    }

    static let symbols: [String] = {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: systemSymbolListPath)),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
              !list.isEmpty
        else {
            return fallbackSymbols
        }
        return list
    }()

    static let recommendedSymbols: [String] = [
        "sparkles",
        "bolt",
        "book",
        "hammer",
        "paintbrush",
        "folder",
        "chart.bar",
        "chart.line.uptrend.xyaxis",
        "clock",
        "calendar",
        "pencil",
        "paperplane",
        "star",
        "flag",
        "heart",
        "leaf",
        "flame",
        "globe",
        "briefcase",
        "graduationcap",
        "brain",
        "camera",
        "music.note",
    ]

    private static let categoryDisplayNames: [(id: String, title: String)] = [
        ("communication", "Comunicación"),
        ("objectsandtools", "Objetos"),
        ("devices", "Dispositivos"),
        ("commerce", "Trabajo"),
        ("home", "Hogar"),
        ("fitness", "Fitness"),
        ("nature", "Naturaleza"),
        ("media", "Media"),
        ("cameraandphotos", "Fotos"),
        ("maps", "Mapas"),
        ("weather", "Clima"),
        ("privacyandsecurity", "Seguridad"),
        ("accessibility", "Accesibilidad"),
        ("shapes", "Formas"),
        ("time", "Tiempo"),
        ("transportation", "Transporte"),
    ]

    static let categories: [SymbolCategory] = {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: systemSymbolCategoriesPath)),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]]
        else {
            return []
        }

        var symbolsForCategory: [String: [String]] = [:]
        for symbol in symbols {
            guard let categories = raw[symbol] else { continue }
            for category in categories {
                symbolsForCategory[category, default: []].append(symbol)
            }
        }

        return categoryDisplayNames.compactMap { entry in
            let list = symbolsForCategory[entry.id] ?? []
            return list.isEmpty ? nil : SymbolCategory(id: entry.id, title: entry.title, symbols: list)
        }
    }()

    static let fallbackSymbols: [String] = [
        "sparkles",
        "bolt",
        "book",
        "hammer",
        "paintbrush",
        "folder",
        "chart.bar",
        "chart.line.uptrend.xyaxis",
        "clock",
        "calendar",
        "pencil",
        "paperplane",
        "star",
        "flag",
        "heart",
        "leaf",
        "flame",
        "globe",
        "briefcase",
        "graduationcap",
        "brain",
        "camera",
        "music.note",
    ]
}
