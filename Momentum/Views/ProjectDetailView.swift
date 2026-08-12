import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    let environment: AppEnvironment
    let project: Project
    var refreshTick: Int

    @State private var draftName: String = ""
    @State private var selectedColor: String = ProjectColorPalette.defaultHex

    private var controller: FocusSessionController { environment.sessionController }

    var body: some View {
        let _ = refreshTick
        let sessions = controller.sessions(for: project)
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if sessions.isEmpty {
                ContentUnavailableView(
                    "Sin sesiones todavía",
                    systemImage: "timer",
                    description: Text("Empieza un foco desde la barra de menús o con ⌃⌥⌘M.")
                )
            } else {
                List(sessions, id: \.persistentModelID) { session in
                    SessionRow(session: session)
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            draftName = project.name
            selectedColor = project.colorHex
        }
        .onChange(of: project.persistentModelID) { _, _ in
            draftName = project.name
            selectedColor = project.colorHex
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(ProjectColor.color(from: project.colorHex))
                    .frame(width: 14, height: 14)
                TextField("Nombre", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .onSubmit {
                        controller.renameProject(project, to: draftName)
                    }
                Spacer()
                Text("Hoy \(DurationFormat.summary(controller.todaySeconds(for: project)))")
                    .foregroundStyle(.secondary)
                Text("7 días \(DurationFormat.summary(controller.weekSeconds(for: project)))")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(ProjectColorPalette.presets, id: \.self) { hex in
                    Circle()
                        .fill(ProjectColor.color(from: hex))
                        .frame(width: 18, height: 18)
                        .overlay {
                            if selectedColor == hex {
                                Circle().strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                        .onTapGesture {
                            selectedColor = hex
                            controller.setProjectColor(project, hex: hex)
                        }
                }
                Spacer()
                if controller.activeProject?.persistentModelID == project.persistentModelID {
                    Button("Detener") {
                        controller.stop(offerNotePrompt: true)
                    }
                } else {
                    Button("Empezar foco") {
                        controller.start(project: project)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .onChange(of: draftName) { _, newValue in
            // Debounced-ish rename on lose focus handled by onSubmit; keep light sync when leaving field via toolbar start.
            if newValue != project.name, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Avoid saving every keystroke — only on submit. No-op here.
            }
        }
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                Spacer()
                Text(DurationFormat.summary(session.duration()))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let note = session.note, !note.isEmpty {
                Text(note)
                    .foregroundStyle(.secondary)
            }
            if session.wasInterrupted {
                Text("Interrumpida (cierre o fallo)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
