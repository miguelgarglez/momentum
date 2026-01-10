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
        RemovableChip(
            title: app?.name ?? identifier,
            showsRemoveButton: false,
            leading: {
                appIcon(for: app)
            },
            onRemove: {},
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
                RemovableChip(
                    title: path.filePathDisplayName,
                    showsRemoveButton: false,
                    leading: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    },
                    onRemove: {},
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
                RemovableChip(
                    title: item,
                    showsLeading: false,
                    showsRemoveButton: false,
                    leading: { EmptyView() },
                    onRemove: {},
                )
            }
        }
    }
}
