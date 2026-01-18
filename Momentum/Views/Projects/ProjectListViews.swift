//
//  ProjectListViews.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Revela tu Momentum")
                .font(.title2.weight(.semibold))
            Text("Crea tu primer proyecto para convertir cada minuto en progreso visible.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)
        }
        .padding()
    }
}

struct EmptyProjectsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sin proyectos aún")
                .font(.headline)
            Text("Añade un proyecto para medir tu dedicación sin fricción.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct ProjectRowView: View {
    let project: Project
    let stats: ProjectRowStats?

    init(project: Project, stats: ProjectRowStats? = nil) {
        self.project = project
        self.stats = stats
    }

    struct ProjectRowStats {
        let totalSeconds: TimeInterval
        let dailySeconds: TimeInterval
        let weeklySeconds: TimeInterval
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(project.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: project.iconName)
                        .foregroundStyle(.white),
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text("Total \(totalText) · Hoy \(dailyText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(weeklyText)
                    .font(.headline)
                Text("Semana")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var totalText: String {
        stats?.totalSeconds.hoursAndMinutesString ?? "…"
    }

    private var dailyText: String {
        stats?.dailySeconds.hoursAndMinutesString ?? "…"
    }

    private var weeklyText: String {
        stats?.weeklySeconds.hoursAndMinutesString ?? "…"
    }
}
