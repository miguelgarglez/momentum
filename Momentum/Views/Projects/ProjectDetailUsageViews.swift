import SwiftUI

struct ContextUsageList: View {
    let summaries: [ContextUsageSummary]

    var body: some View {
        let maxSeconds = summaries.map(\.seconds).max() ?? 1
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
            strokeOpacity: 0.12,
        )
    }
}

struct LastUsedSessionSnapshot: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let bundleIdentifier: String?
    let domain: String?
    let filePath: String?
    let duration: TimeInterval
    let endDate: Date

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String?,
        bundleIdentifier: String?,
        domain: String?,
        filePath: String?,
        duration: TimeInterval,
        endDate: Date,
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.bundleIdentifier = bundleIdentifier
        self.domain = domain
        self.filePath = filePath
        self.duration = duration
        self.endDate = endDate
    }

    init(session: TrackingSession) {
        id = UUID()
        title = session.primaryContextLabel
        subtitle = session.secondaryContextLabel
        bundleIdentifier = session.bundleIdentifier
        domain = session.domain
        filePath = session.filePath
        duration = session.duration
        endDate = session.endDate
    }
}

struct LastUsedCard: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    let snapshot: LastUsedSessionSnapshot

    init(snapshot: LastUsedSessionSnapshot) {
        self.snapshot = snapshot
    }

    init(session: TrackingSession) {
        snapshot = LastUsedSessionSnapshot(session: session)
    }

    private var title: String { snapshot.title }
    private var subtitle: String? { snapshot.subtitle }

    private var icon: Image {
        if snapshot.filePath != nil {
            return Image(systemName: "doc.text")
        }
        if let bundle = snapshot.bundleIdentifier,
           let app = appCatalog.app(for: bundle)
        {
            return app.icon
        }
        return Image(systemName: snapshot.domain == nil ? "app" : "globe")
    }

    private var relativeTime: String {
        Self.relativeDateFormatter.localizedString(for: snapshot.endDate, relativeTo: .now)
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
                Text(snapshot.duration.hoursAndMinutesString)
                    .font(.headline)
            }

            Text(String(localized: "Último registro: \(relativeTime)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12,
        )
    }
}

private extension LastUsedCard {
    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
