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
        VStack(alignment: .leading, spacing: 12) {
            Text("Todo listo para empezar")
                .font(.headline)
            Text("Cuando inicies tracking, Momentum registrará las apps y dominios que uses para asociarlos a este proyecto.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Puedes pausar o detener el tracking cuando quieras.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Iniciar tracking") {
                onStartTracking()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("project-empty-start-tracking")
        }
        .detailCardStyle(padding: 18, cornerRadius: 18, strokeOpacity: 0.08)
    }
}
