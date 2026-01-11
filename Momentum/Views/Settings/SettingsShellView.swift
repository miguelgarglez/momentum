import SwiftUI

struct SettingsShellView: View {
    @EnvironmentObject private var settings: TrackerSettings
    @EnvironmentObject private var themePreview: ThemePreviewState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var navigationModel = SettingsNavigationModel(selection: .tracking)
    @State private var draft = TrackerSettingsDraft()
    @State private var hasLoadedDraft = false
    private enum Layout {
        static let minWidth: CGFloat = 560
        static let minHeight: CGFloat = 420
    }

    var body: some View {
        HSplitView {
            SettingsSidebarView(selection: $navigationModel.selection)
                .navigationTitle("Configuración")
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 210)
                .background(Color(nsColor: .controlBackgroundColor))
            VStack(spacing: 0) {
                NavigationStack {
                    TrackerSettingsView(
                        draft: $draft,
                        section: navigationModel.selection ?? .tracking,
                    )
                }
                Divider()
                HStack(spacing: 12) {
                    Spacer()
                    Button("Cerrar") {
                        Task { @MainActor in
                            discardChanges()
                            dismiss()
                        }
                    }
                    Button("Guardar") {
                        applyChanges()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .environmentObject(navigationModel)
        .frame(minWidth: Layout.minWidth, minHeight: Layout.minHeight)
        #if os(macOS)
        .background(WindowCloseObserver {
            Task { @MainActor in
                discardChanges()
            }
        })
        #endif
        .onAppear {
            if !hasLoadedDraft {
                draft = TrackerSettingsDraft(from: settings)
                hasLoadedDraft = true
            }
            if themePreview.selection == nil {
                themePreview.selection = settings.themePreference
            }
        }
        .task(id: themePreview.selection) {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                themePreview.previewPreference = themePreview.selection
            }
        }
    }

    @MainActor
    private func applyChanges() {
        settings.isDomainTrackingEnabled = draft.isDomainTrackingEnabled
        settings.isFileTrackingEnabled = draft.isFileTrackingEnabled
        settings.detectionInterval = draft.detectionInterval
        settings.idleThresholdMinutes = draft.idleThresholdMinutes
        settings.excludedApps = draft.excludedApps
        settings.excludedDomains = draft.excludedDomains
        settings.excludedFiles = draft.excludedFiles
        settings.isDatabaseEncryptionEnabled = draft.isDatabaseEncryptionEnabled
        settings.assignmentRuleExpiration = draft.assignmentRuleExpiration
        settings.themePreference = themePreview.selection ?? settings.themePreference
        clearThemePreview()
    }

    private func clearThemePreview() {
        themePreview.selection = nil
        themePreview.previewPreference = nil
    }

    @MainActor
    private func discardChanges() {
        draft = TrackerSettingsDraft(from: settings)
        clearThemePreview()
    }
}

#Preview {
    SettingsShellView()
}
