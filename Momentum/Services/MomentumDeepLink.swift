import Foundation

#if os(macOS)
    import AppKit
#endif

enum MomentumDeepLink {
    static let scheme = "momentum"

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let section = components?.queryItems?.first(where: { $0.name == "section" })?.value

        if host == "settings" || url.path.lowercased().hasPrefix("/settings") {
            openSettings(section: section)
            return true
        }

        return false
    }

    static func openSettings(section: String?) {
        SettingsWindowPresenter.open(section: section)
    }
}
