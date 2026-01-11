import Foundation
import SwiftUI

struct SettingsPrivacySectionView: View {
    @Binding var draft: TrackerSettingsDraft
    let projects: [Project]
    @Binding var showEraseAllConfirmation: Bool
    @Binding var showingEncryptionInfo: Bool
    @Binding var projectPendingDeletion: Project?

    var body: some View {
        Section {
            Toggle(isOn: $draft.isDatabaseEncryptionEnabled) {
                HStack(spacing: 6) {
                    Text("Cifrar base de datos")
                    Button {
                        showingEncryptionInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Más información")
                }
            }

            Button(role: .destructive) {
                showEraseAllConfirmation = true
            } label: {
                Label("Borrar todos los datos", systemImage: "trash")
            }

            if projects.isEmpty {
                Text("No hay proyectos para limpiar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(projects) { project in
                        Button(role: .destructive) {
                            projectPendingDeletion = project
                        } label: {
                            Text(project.name)
                        }
                    }
                } label: {
                    Label("Borrar actividad de un proyecto", systemImage: "folder.badge.minus")
                }
            }
        } header: {
            SettingsSectionHeader(
                "Privacidad y datos",
                subtitle: "Gestiona la protección de tu base de datos y limpieza de actividad.",
            )
        }
    }
}
