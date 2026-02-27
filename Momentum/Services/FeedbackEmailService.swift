import Foundation
#if os(macOS)
    import AppKit
#endif

struct FeedbackEmailContext: Equatable {
    var appVersion: String?
    var buildNumber: String?
    var osVersion: String?
    var localeIdentifier: String?
    var trackingState: String?
    var appName: String?
    var domain: String?
    var filePath: String?
}

@MainActor
final class FeedbackEmailService {
    static let supportAddress = "miguel.garglez@gmail.com"
    private static let unavailable = "N/A"

    private let bundle: Bundle
    private let localeProvider: () -> Locale
    private let osVersionProvider: () -> String
    private let openURL: (URL) -> Bool

    init(
        bundle: Bundle = .main,
        localeProvider: @escaping () -> Locale = { Locale.current },
        osVersionProvider: @escaping () -> String = { ProcessInfo.processInfo.operatingSystemVersionString },
        openURL: @escaping (URL) -> Bool = { url in
            #if os(macOS)
                NSWorkspace.shared.open(url)
            #else
                false
            #endif
        },
    ) {
        self.bundle = bundle
        self.localeProvider = localeProvider
        self.osVersionProvider = osVersionProvider
        self.openURL = openURL
    }

    func makeContext(statusSummary: ActivityTracker.StatusSummary?) -> FeedbackEmailContext {
        FeedbackEmailContext(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            osVersion: osVersionProvider(),
            localeIdentifier: localeProvider().identifier,
            trackingState: statusSummary.map(stateLabel(for:)),
            appName: statusSummary?.appName,
            domain: statusSummary?.domain,
            filePath: statusSummary?.filePath?.filePathDisplayName,
        )
    }

    func makeMailtoURL(context: FeedbackEmailContext) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[Momentum] Feedback"),
            URLQueryItem(name: "body", value: makeBody(context: context)),
        ]
        return components.url
    }

    @discardableResult
    func sendFeedbackEmail(statusSummary: ActivityTracker.StatusSummary?) -> Bool {
        let context = makeContext(statusSummary: statusSummary)
        return sendFeedbackEmail(context: context)
    }

    @discardableResult
    func sendFeedbackEmail(context: FeedbackEmailContext) -> Bool {
        guard let url = makeMailtoURL(context: context) else { return false }
        return openURL(url)
    }

    private func makeBody(context: FeedbackEmailContext) -> String {
        let versionText: String
        switch (safe(context.appVersion), safe(context.buildNumber)) {
        case let (version, build) where version != Self.unavailable && build != Self.unavailable:
            versionText = "\(version) (\(build))"
        case let (version, _) where version != Self.unavailable:
            versionText = version
        case let (_, build) where build != Self.unavailable:
            versionText = build
        default:
            versionText = Self.unavailable
        }

        let lines = [
            String(localized: "Tipo: Bug | Mejora | Feedback"),
            "",
            String(localized: "Descripción:"),
            "",
            String(localized: "Pasos para reproducir (si aplica):"),
            "",
            String(localized: "Resultado esperado:"),
            "",
            String(localized: "Resultado actual:"),
            "",
            "---",
            String(localized: "Contexto técnico"),
            String.localizedStringWithFormat(String(localized: "- Versión app: %@"), versionText),
            String.localizedStringWithFormat(String(localized: "- macOS: %@"), safe(context.osVersion)),
            String.localizedStringWithFormat(String(localized: "- Idioma/locale: %@"), safe(context.localeIdentifier)),
            String.localizedStringWithFormat(String(localized: "- Estado tracking: %@"), safe(context.trackingState)),
            String.localizedStringWithFormat(String(localized: "- App activa: %@"), safe(context.appName)),
            String.localizedStringWithFormat(String(localized: "- Dominio: %@"), safe(context.domain)),
            String.localizedStringWithFormat(String(localized: "- Archivo: %@"), safe(context.filePath)),
        ]
        return lines.joined(separator: "\n")
    }

    private func safe(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.unavailable
        }
        return value
    }

    private func stateLabel(for summary: ActivityTracker.StatusSummary) -> String {
        switch summary.state {
        case .inactive:
            String(localized: "Sin tracking")
        case .tracking:
            String(localized: "Tracking activo")
        case .trackingManual:
            String(localized: "Tracking manual activo")
        case .pendingResolution:
            String(localized: "Pendiente de asignación")
        case .pausedManual:
            String(localized: "Tracking pausado")
        case .pausedIdle:
            String(localized: "Tracking pausado (idle)")
        case .pausedScreenLocked:
            String(localized: "Tracking pausado (bloqueo)")
        case .pausedExcluded:
            String(localized: "Actividad excluida")
        }
    }
}
