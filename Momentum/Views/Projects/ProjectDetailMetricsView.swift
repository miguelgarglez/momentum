import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
            Text(NSLocalizedString(subtitle, comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(
            maxWidth: ProjectDetailView.MetricLayout.maxWidth,
            minHeight: ProjectDetailView.MetricLayout.minHeight,
            alignment: .bottomLeading,
        )
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12,
        )
    }
}

struct HighlightMetricRow: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint),
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(title, comment: ""))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                Text(NSLocalizedString(subtitle, comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .detailInsetStyle(
            cornerRadius: 14,
            strokeOpacity: 0.12,
        )
    }
}

struct DetailMetaPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.12)),
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1),
        )
        .foregroundStyle(tint)
    }
}
