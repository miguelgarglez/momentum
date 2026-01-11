import SwiftUI

struct SettingsAppearanceSectionView: View {
    @Binding var themeSelection: AppThemePreference
    @EnvironmentObject private var themePreview: ThemePreviewState

    var body: some View {
        Section {
            Picker("Tema", selection: $themeSelection) {
                ForEach(AppThemePreference.allCases) { option in
                    Text(option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .transaction { $0.disablesAnimations = true }
            .animation(.none, value: themePreview.selection)
        } header: {
            SettingsSectionHeader(
                "Apariencia",
                subtitle: "Ajusta el tema visual que verás en toda la app.",
            )
        }
    }
}
