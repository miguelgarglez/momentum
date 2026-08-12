import SwiftData
import SwiftUI

struct ProjectsSidebar: View {
    let environment: AppEnvironment
    @Binding var selectedProjectID: PersistentIdentifier?
    var refreshTick: Int

    private var controller: FocusSessionController { environment.sessionController }

    var body: some View {
        let _ = refreshTick
        let projects = controller.allProjects()
        List(selection: $selectedProjectID) {
            Section("Proyectos") {
                ForEach(projects, id: \.persistentModelID) { project in
                    ProjectRow(
                        project: project,
                        today: controller.todaySeconds(for: project),
                        week: controller.weekSeconds(for: project),
                        isActive: controller.activeProject?.persistentModelID == project.persistentModelID
                    )
                    .tag(project.persistentModelID)
                    .contextMenu {
                        Button("Empezar foco") {
                            controller.start(project: project)
                        }
                        Divider()
                        Button("Eliminar", role: .destructive) {
                            if selectedProjectID == project.persistentModelID {
                                selectedProjectID = nil
                            }
                            controller.deleteProject(project)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("Hoy · \(DurationFormat.summary(controller.todaySecondsTotal()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let today: TimeInterval
    let week: TimeInterval
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ProjectColor.color(from: project.colorHex))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(project.name)
                        .fontWeight(isActive ? .semibold : .regular)
                    if isActive {
                        Text("EN FOCO")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
                Text("Hoy \(DurationFormat.summary(today)) · 7d \(DurationFormat.summary(week))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
