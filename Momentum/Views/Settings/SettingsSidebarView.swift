import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selection: SettingsSection?

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.allCases) { section in
                NavigationLink(value: section) {
                    Label(section.label, systemImage: section.systemImageName)
                        .font(.headline)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    SettingsSidebarView(selection: .constant(.tracking))
}
