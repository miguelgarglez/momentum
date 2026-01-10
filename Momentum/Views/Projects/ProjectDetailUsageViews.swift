import SwiftUI

struct ContextUsageList: View {
    let summaries: [ContextUsageSummary]

    var body: some View {
        let maxSeconds = summaries.map { $0.seconds }.max() ?? 1
        VStack(spacing: 12) {
            ForEach(summaries) { summary in
                ContextUsageRow(summary: summary, maxSeconds: maxSeconds)
            }
        }
    }
}

struct ContextUsageRow: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    let summary: ContextUsageSummary
    let maxSeconds: TimeInterval

    private var icon: Image {
        if summary.filePath != nil {
            return Image(systemName: "doc.text")
        }
        if let bundle = summary.bundleIdentifier,
           let app = appCatalog.app(for: bundle)
        {
            return app.icon
        }
        return Image(systemName: summary.domain == nil ? "app" : "globe")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                icon
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle = summary.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(summary.seconds.hoursAndMinutesString)
                    .font(.subheadline.bold())
            }

            ProgressView(value: summary.seconds, total: maxSeconds)
                .progressViewStyle(.linear)
        }
        .padding()
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12
        )
    }
}

struct LastUsedCard: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    let session: TrackingSession

    private var title: String { session.primaryContextLabel }
    private var subtitle: String? { session.secondaryContextLabel }

    private var icon: Image {
        if session.filePath != nil {
            return Image(systemName: "doc.text")
        }
        if let bundle = session.bundleIdentifier,
           let app = appCatalog.app(for: bundle)
        {
            return app.icon
        }
        return Image(systemName: session.domain == nil ? "app" : "globe")
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: session.endDate, relativeTo: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                icon
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.bold())
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(session.duration.hoursAndMinutesString)
                    .font(.headline)
            }

            Text("Último registro: \(relativeTime)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12
        )
    }
}
