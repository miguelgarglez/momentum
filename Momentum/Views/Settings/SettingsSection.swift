import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case tracking
    case raycast
    case privacy
    case appearance
    case idle
    case exclusions
    case assignmentRules

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tracking:
            "Tracking"
        case .raycast:
            "Raycast Extension"
        case .privacy:
            "Privacidad"
        case .appearance:
            "Apariencia"
        case .idle:
            "Inactividad"
        case .exclusions:
            "Exclusiones"
        case .assignmentRules:
            "Reglas"
        }
    }

    var systemImageName: String {
        switch self {
        case .tracking:
            "dot.scope"
        case .raycast:
            "command"
        case .privacy:
            "lock.shield"
        case .appearance:
            "paintbrush"
        case .idle:
            "moon.zzz"
        case .exclusions:
            "line.3.horizontal.decrease.circle"
        case .assignmentRules:
            "point.3.connected.trianglepath.dotted"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selection: SettingsSection?

    init(selection: SettingsSection? = .tracking) {
        self.selection = selection
    }
}
