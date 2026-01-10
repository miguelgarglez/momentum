//
//  AutomationPermissionPromptView.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftUI

struct AutomationPermissionPromptView: View {
    let onOpenSettings: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Permisos para archivos y dominios")
                    .font(.title2.weight(.semibold))
                Text("Para identificar archivos o dominios activos, macOS mostrará un diálogo de permisos.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Recogemos: nombre de la app, dominio o archivo activo.", systemImage: "checkmark.circle")
                Label("Nunca: contenido, teclas ni capturas de pantalla.", systemImage: "xmark.circle")
                Label("Toda la información se guarda localmente en tu ordenador.", systemImage: "lock.shield")
                Label("Solo se solicita cuando detectamos una app compatible.", systemImage: "info.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Button("Abrir Ajustes") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("accessibility-permission-open-settings")

                Spacer()

                Button("Entendido") {
                    onLater()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("accessibility-permission-acknowledge")
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 520)
    }
}
