import SwiftUI

struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = NSLocalizedString(title, comment: "")
        self.subtitle = subtitle.map { NSLocalizedString($0, comment: "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}
