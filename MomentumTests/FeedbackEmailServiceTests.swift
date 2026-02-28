import Foundation
@testable import Momentum
import Testing

@MainActor
struct FeedbackEmailServiceTests {
    @Test("Genera URL mailto válida con asunto y body")
    func makeMailtoURLIncludesExpectedPayload() {
        let service = FeedbackEmailService(
            bundle: .main,
            localeProvider: { Locale(identifier: "es_ES") },
            osVersionProvider: { "macOS 15.0" },
            openURL: { _ in true },
        )
        let context = FeedbackEmailContext(
            appVersion: "1.7.0",
            buildNumber: "202602010101",
            osVersion: "macOS 15.0",
            localeIdentifier: "es_ES",
            trackingState: "Tracking activo",
            appName: "Safari",
            domain: "example.com",
            filePath: "notes.md",
        )

        let url = service.makeMailtoURL(context: context)
        #expect(url != nil)
        guard let url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.scheme == "mailto")
        #expect(components?.path == FeedbackEmailService.supportAddress)
        let subject = components?.queryItems?.first(where: { $0.name == "subject" })?.value
        #expect(subject == "[Momentum] Feedback")
        let body = components?.queryItems?.first(where: { $0.name == "body" })?.value
        let typeLine = String(localized: "Tipo: Bug | Mejora | Feedback")
        let trackingLine = String.localizedStringWithFormat(String(localized: "- Estado tracking: %@"), "Tracking activo")
        let domainLine = String.localizedStringWithFormat(String(localized: "- Dominio: %@"), "example.com")
        #expect(body?.contains(typeLine) == true)
        #expect(body?.contains(trackingLine) == true)
        #expect(body?.contains(domainLine) == true)
    }

    @Test("Body usa N/A cuando faltan campos")
    func makeMailtoURLUsesFallbackForMissingData() {
        let service = FeedbackEmailService(
            bundle: .main,
            localeProvider: { Locale(identifier: "") },
            osVersionProvider: { "" },
            openURL: { _ in true },
        )
        let context = FeedbackEmailContext()
        let url = service.makeMailtoURL(context: context)
        #expect(url != nil)
        guard let url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let body = components?.queryItems?.first(where: { $0.name == "body" })?.value
        let appVersionFallback = String.localizedStringWithFormat(String(localized: "- Versión app: %@"), "N/A")
        let osFallback = String.localizedStringWithFormat(String(localized: "- macOS: %@"), "N/A")
        let fileFallback = String.localizedStringWithFormat(String(localized: "- Archivo: %@"), "N/A")
        #expect(body?.contains(appVersionFallback) == true)
        #expect(body?.contains(osFallback) == true)
        #expect(body?.contains(fileFallback) == true)
    }

    @Test("sendFeedbackEmail delega apertura de URL")
    func sendFeedbackEmailUsesOpenHandler() {
        var openedURL: URL?
        let service = FeedbackEmailService(
            bundle: .main,
            localeProvider: { Locale(identifier: "en_US") },
            osVersionProvider: { "macOS" },
            openURL: { url in
                openedURL = url
                return true
            },
        )

        let opened = service.sendFeedbackEmail(context: FeedbackEmailContext(appVersion: "1.0"))
        #expect(opened)
        #expect(openedURL != nil)
        #expect(openedURL?.scheme == "mailto")
    }
}
