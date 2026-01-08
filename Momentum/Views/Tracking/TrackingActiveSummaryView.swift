//
//  TrackingActiveSummaryView.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftUI

struct TrackingActiveSummaryView: View {
    let elapsed: TimeInterval
    let apps: [String]
    let domains: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.green)
                Text("Tracking activo")
                    .font(.headline)
                Spacer()
                Text(elapsed.minutesOrHoursMinutesString)
                    .font(.subheadline.weight(.semibold))
            }

            if !apps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apps detectadas")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(apps, id: \.self) { app in
                            TrackingChip(text: app)
                        }
                    }
                }
            }

            if !domains.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dominios detectados")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(domains, id: \.self) { domain in
                            TrackingChip(text: domain)
                        }
                    }
                }
            }
        }
        .detailCardStyle(padding: 18, cornerRadius: 18, strokeOpacity: 0.08)
    }
}

private struct TrackingChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
