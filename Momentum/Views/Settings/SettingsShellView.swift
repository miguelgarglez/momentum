import SwiftUI

struct SettingsShellView: View {
    @StateObject private var navigationModel = SettingsNavigationModel(selection: .tracking)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private enum Layout {
        static let minWidth: CGFloat = 720
        static let minHeight: CGFloat = 520
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebarView(selection: $navigationModel.selection)
                .navigationTitle("Configuración")
        } detail: {
            TrackerSettingsView()
        }
        .environmentObject(navigationModel)
        .frame(minWidth: Layout.minWidth, minHeight: Layout.minHeight)
    }
}

#Preview {
    SettingsShellView()
}
