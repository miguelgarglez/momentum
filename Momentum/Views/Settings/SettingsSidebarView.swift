import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selection: SettingsSection?

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.allCases) { section in
                NavigationLink(value: section) {
                    Label(section.label, systemImage: section.systemImageName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .focusable(true)
                .accessibilityLabel(Text(section.label))
                .accessibilityHint(Text("Abre la sección \(section.label)."))
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    SettingsSidebarView(
        selection: .constant(.tracking),
    )
}
