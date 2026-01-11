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
            #if os(macOS)
                Text("Momentum aparece en el Dock solo cuando hay ventanas visibles y vuelve al modo barra de menús al cerrarlas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            #endif
        } header: {
            SettingsSectionHeader(
                "Apariencia",
                subtitle: "Ajusta el tema visual que verás en toda la app.",
            )
        }
    }
}
