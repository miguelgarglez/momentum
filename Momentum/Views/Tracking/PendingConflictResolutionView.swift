//
//  PendingConflictResolutionView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI
import SwiftData

struct PendingConflictBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pendiente de asignación")
                    .font(.subheadline.weight(.semibold))
                Text("Tienes \(count) contexto(s) por resolver.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Resolver") {
                action()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("pending-conflict-resolve-button")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-conflict-banner")
    }
}

struct PendingConflictResolutionView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss

    let pendingSessions: [PendingTrackingSession]
    let projects: [Project]

    @State private var selections: [String: PersistentIdentifier] = [:]

    var body: some View {
        let conflicts = PendingConflict.grouped(from: pendingSessions, projects: projects)

        NavigationStack {
            Group {
                if conflicts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No hay conflictos pendientes.")
                            .font(.headline)
                        Text("Cuando aparezcan, podrás resolverlos aquí.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(conflicts) { conflict in
                                PendingConflictRow(
                                    conflict: conflict,
                                    selection: Binding(
                                        get: { selections[conflict.id] },
                                        set: { selections[conflict.id] = $0 }
                                    ),
                                    onResolve: { project in
                                        tracker.resolveConflict(context: conflict.context, project: project)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Resolver conflictos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-conflict-sheet")
    }
}

private struct PendingConflictRow: View {
    let conflict: PendingConflict
    @Binding var selection: PersistentIdentifier?
    let onResolve: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.title)
                        .font(.headline)
                    if let subtitle = conflict.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(conflict.totalSeconds.hoursAndMinutesString)
                    .font(.subheadline.weight(.semibold))
            }

            Picker("Proyecto", selection: $selection) {
                ForEach(conflict.candidates) { project in
                    Text(project.name)
                        .tag(project.persistentModelID)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("pending-conflict-project-picker-\(conflict.id)")

            Button("Asignar") {
                guard let selection,
                      let project = conflict.candidates.first(where: { $0.persistentModelID == selection }) else { return }
                onResolve(project)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection == nil)
            .accessibilityIdentifier("pending-conflict-assign-button-\(conflict.id)")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-conflict-row-\(conflict.id)")
        .onAppear {
            if selection == nil {
                selection = conflict.candidates.first?.persistentModelID
            }
        }
    }
}

struct PendingConflict: Identifiable {
    let id: String
    let context: AssignmentContext
    let title: String
    let subtitle: String?
    let totalSeconds: TimeInterval
    let candidates: [Project]

    static func grouped(from sessions: [PendingTrackingSession], projects: [Project]) -> [PendingConflict] {
        let grouped = Dictionary(grouping: sessions) { "\($0.contextType)::\($0.contextValue)" }

        return grouped.compactMap { key, items in
            guard let first = items.first else { return nil }
            let type = AssignmentContextType(rawValue: first.contextType) ?? .app
            let context = AssignmentContext(type: type, value: first.contextValue)
            let candidates = projects.filter { project in
                switch type {
                case .app:
                    return project.matches(appBundleIdentifier: first.contextValue)
                case .domain:
                    return project.matches(domain: first.contextValue)
                }
            }
            guard !candidates.isEmpty else { return nil }
            let totalSeconds = items.reduce(0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate)) }
            let title: String
            let subtitle: String?
            switch type {
            case .app:
                title = first.appName
                subtitle = first.bundleIdentifier ?? first.contextValue
            case .domain:
                title = first.contextValue
                subtitle = first.appName
            }

            return PendingConflict(
                id: key,
                context: context,
                title: title,
                subtitle: subtitle,
                totalSeconds: totalSeconds,
                candidates: candidates
            )
        }
        .sorted { $0.totalSeconds > $1.totalSeconds }
    }
}
