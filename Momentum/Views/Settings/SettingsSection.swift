import Foundation

@MainActor
enum SettingsSection: String, CaseIterable, Identifiable {
    case tracking
    case privacy
    case appearance
    case idle
    case exclusions
    case assignmentRules

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tracking:
            return "Tracking automatico"
        case .privacy:
            return "Privacidad y datos"
        case .appearance:
            return "Apariencia"
        case .idle:
            return "Inactividad"
        case .exclusions:
            return "Exclusiones globales"
        case .assignmentRules:
            return "Reglas de asignacion"
        }
    }

    var systemImageName: String {
        switch self {
        case .tracking:
            return "dot.scope"
        case .privacy:
            return "lock.shield"
        case .appearance:
            return "paintbrush"
        case .idle:
            return "moon.zzz"
        case .exclusions:
            return "line.3.horizontal.decrease.circle"
        case .assignmentRules:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selection: SettingsSection?

    init(selection: SettingsSection? = nil) {
        self.selection = selection
    }
}
