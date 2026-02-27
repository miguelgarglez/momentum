import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case tracking
    case raycast
    case feedback
    case privacy
    case appearance
    case idle
    case exclusions
    case assignmentRules

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tracking:
            String(localized: "Tracking")
        case .raycast:
            String(localized: "Raycast Extension")
        case .feedback:
            String(localized: "Feedback")
        case .privacy:
            String(localized: "Privacidad")
        case .appearance:
            String(localized: "Apariencia")
        case .idle:
            String(localized: "Inactividad")
        case .exclusions:
            String(localized: "Exclusiones")
        case .assignmentRules:
            String(localized: "Reglas")
        }
    }

    var systemImageName: String {
        switch self {
        case .tracking:
            "dot.scope"
        case .raycast:
            "command"
        case .feedback:
            "bubble.left.and.bubble.right"
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
