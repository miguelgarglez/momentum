import Foundation

@MainActor
final class ThemePreviewState: ObservableObject {
    @Published var selection: AppThemePreference?
    @Published var previewPreference: AppThemePreference?

    init(selection: AppThemePreference? = nil, previewPreference: AppThemePreference? = nil) {
        self.selection = selection
        self.previewPreference = previewPreference
    }
}
