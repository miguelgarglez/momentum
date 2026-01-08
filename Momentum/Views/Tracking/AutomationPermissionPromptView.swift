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
                Text("Permisos para dominios")
                    .font(.title2.weight(.semibold))
                Text("Para identificar dominios en Safari o Chrome, macOS mostrará un diálogo de permisos.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Recogemos: nombre de la app y dominio del navegador.", systemImage: "checkmark.circle")
                Label("Nunca: contenido, teclas ni capturas de pantalla.", systemImage: "xmark.circle")
                Label("Solo se solicita cuando detectamos un navegador activo.", systemImage: "info.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Button("Más tarde") {
                    onLater()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("accessibility-permission-later")

                Spacer()

                Button("Abrir ajustes") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("accessibility-permission-open-settings")
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 520)
    }
}
