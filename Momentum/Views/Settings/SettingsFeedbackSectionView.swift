import SwiftUI

struct SettingsFeedbackSectionView: View {
    let statusSummary: ActivityTracker.StatusSummary?
    private let feedbackEmailService: FeedbackEmailService
    @State private var feedbackEmailError: String?

    init(
        statusSummary: ActivityTracker.StatusSummary?,
        feedbackEmailService: FeedbackEmailService = FeedbackEmailService(),
    ) {
        self.statusSummary = statusSummary
        self.feedbackEmailService = feedbackEmailService
    }

    var body: some View {
        Section {
            Text("Comparte bugs, mejoras o ideas por correo. Leeré cada mensaje.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Enviar feedback") {
                let context = feedbackEmailService.makeContext(statusSummary: statusSummary)
                let opened = feedbackEmailService.sendFeedbackEmail(context: context)
                feedbackEmailError = opened ? nil : String(localized: "No pudimos abrir el cliente de correo.")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("feedback-send-email-button")

            Text("Incluye bug, mejora o comentario general.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let feedbackEmailError {
                Text(feedbackEmailError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            SettingsSectionHeader(
                "Feedback",
                subtitle: "Envía comentarios directamente por email para mejorar Momentum.",
            )
        }
    }
}
