//
//  PendingConflictResolutionView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftData
import SwiftUI

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
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.6), lineWidth: 1),
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
                                        set: { selections[conflict.id] = $0 },
                                    ),
                                    onResolve: { project in
                                        tracker.resolveConflict(context: conflict.context, project: project)
                                    },
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
    @EnvironmentObject private var appCatalog: AppCatalog

    let conflict: PendingConflict
    @Binding var selection: PersistentIdentifier?
    let onResolve: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                contextIcon
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
                if conflict.totalSeconds > 0 {
                    Text(conflict.totalSeconds.hoursAndMinutesString)
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Sin registro pendiente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                selectedProjectBadge

                Picker("Proyecto", selection: $selection) {
                    ForEach(conflict.candidates) { project in
                        Label(project.name, systemImage: ProjectIcon(rawValue: project.iconName)?.systemName ?? "folder")
                            .tag(project.persistentModelID)
                    }
                }
                #if os(macOS)
                .pickerStyle(.automatic)
                #else
                .pickerStyle(.menu)
                #endif
                .labelsHidden()
                .accessibilityIdentifier("pending-conflict-project-picker-\(conflict.id)")

                Spacer()

                Button("Asignar") {
                    guard let selection,
                          let project = conflict.candidates.first(where: { $0.persistentModelID == selection }) else { return }
                    onResolve(project)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selection == nil)
                .accessibilityIdentifier("pending-conflict-assign-button-\(conflict.id)")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08)),
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-conflict-row-\(conflict.id)")
        .onAppear {
            if selection == nil {
                selection = conflict.candidates.first?.persistentModelID
            }
        }
    }

    @ViewBuilder
    private var contextIcon: some View {
        let size: CGFloat = 34
        switch conflict.context.type {
        case .app:
            contextAppIcon(bundleIdentifier: conflict.bundleIdentifier ?? conflict.context.value, size: size)
        case .domain:
            if let bundleIdentifier = conflict.bundleIdentifier {
                contextAppIcon(bundleIdentifier: bundleIdentifier, size: size)
            } else {
                contextFallbackIcon(systemName: "globe", size: size)
            }
        case .file:
            if let bundleIdentifier = conflict.bundleIdentifier {
                contextAppIcon(bundleIdentifier: bundleIdentifier, size: size)
            } else {
                contextFallbackIcon(systemName: "doc.text", size: size)
            }
        }
    }

    @ViewBuilder
    private func contextAppIcon(bundleIdentifier: String, size: CGFloat) -> some View {
        #if os(macOS)
            if let app = appCatalog.app(for: bundleIdentifier) {
                app.icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                contextFallbackIcon(systemName: "app.fill", size: size)
            }
        #else
            contextFallbackIcon(systemName: "app.fill", size: size)
        #endif
    }

    private func contextFallbackIcon(systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: size, height: size)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var selectedProject: Project? {
        conflict.candidates.first { $0.persistentModelID == selection }
    }

    private var selectedProjectBadge: some View {
        let project = selectedProject
        let color = project?.color ?? Color.secondary.opacity(0.25)
        let iconName = ProjectIcon(rawValue: project?.iconName ?? "")?.systemName ?? "folder"
        return ZStack {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .accessibilityHidden(true)
    }
}

struct PendingConflict: Identifiable {
    let id: String
    let context: AssignmentContext
    let bundleIdentifier: String?
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
                    project.matches(appBundleIdentifier: first.contextValue)
                case .domain:
                    project.matches(domain: first.contextValue)
                case .file:
                    project.matches(filePath: first.contextValue)
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
            case .file:
                title = first.contextValue.filePathDisplayName
                subtitle = first.contextValue
            }

            return PendingConflict(
                id: key,
                context: context,
                bundleIdentifier: first.bundleIdentifier,
                title: title,
                subtitle: subtitle,
                totalSeconds: totalSeconds,
                candidates: candidates,
            )
        }
        .sorted { $0.totalSeconds > $1.totalSeconds }
    }
}
