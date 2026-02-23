//
//  ProjectEmptyStateView.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftUI

struct ProjectEmptyStateView: View {
    let onStartTracking: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Todo listo para empezar")
                .font(.headline)
            Text("Usa cualquiera de estas 3 vías para registrar tiempo en este proyecto:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                emptyStateRow(
                    icon: "bolt.circle",
                    title: "Auto-tracking",
                    detail: "Momentum detecta apps, dominios y archivos asignados y registra tiempo automáticamente."
                )
                emptyStateRow(
                    icon: "record.circle",
                    title: "Manual en vivo",
                    detail: "Empieza y detén el tracking intencionalmente cuando vayas a dedicarte a este proyecto."
                )
                emptyStateRow(
                    icon: "plus.circle",
                    title: "Añadir tiempo manual",
                    detail: "Suma tiempo pasado (por ejemplo, trabajo en otro dispositivo) sin iniciar tracking."
                )
            }

            Button("Iniciar manual en vivo") {
                onStartTracking()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("project-empty-start-tracking")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCardStyle(padding: 18, cornerRadius: 18, strokeOpacity: 0.08)
    }

    @ViewBuilder
    private func emptyStateRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
