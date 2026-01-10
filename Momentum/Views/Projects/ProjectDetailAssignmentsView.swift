import SwiftUI

struct AssignedAppsChips: View {
    @EnvironmentObject private var appCatalog: AppCatalog
    let bundleIdentifiers: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(bundleIdentifiers, id: \.self) { identifier in
                chip(for: identifier)
            }
        }
    }

    @ViewBuilder
    private func chip(for identifier: String) -> some View {
        let app = appCatalog.app(for: identifier)
        HStack(spacing: 8) {
            appIcon(for: app)
            Text(app?.name ?? identifier)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .help(app?.bundleIdentifier ?? identifier)
    }

    @ViewBuilder
    private func appIcon(for app: InstalledApp?) -> some View {
        (app?.icon ?? Image(systemName: "app"))
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct AssignedFilesChips: View {
    let filePaths: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(filePaths, id: \.self) { path in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .semibold))
                    Text(path.filePathDisplayName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .help(path)
            }
        }
    }
}

struct WrappingChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }
}
