import SwiftUI

struct SettingsShellView: View {
    @StateObject private var navigationModel = SettingsNavigationModel(selection: .tracking)

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(selection: $navigationModel.selection)
                .navigationTitle("Configuración")
        } detail: {
            TrackerSettingsView()
        }
    }
}

#Preview {
    SettingsShellView()
}
