import SwiftData
import SwiftUI

struct ContentView: View {
    let environment: AppEnvironment

    @State private var selectedProjectID: PersistentIdentifier?
    @State private var showNewProject = false
    @State private var noteDraft = ""
    @State private var refreshTick = 0

    private var controller: FocusSessionController { environment.sessionController }

    var body: some View {
        NavigationSplitView {
            ProjectsSidebar(
                environment: environment,
                selectedProjectID: $selectedProjectID,
                refreshTick: refreshTick
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let project = selectedProject(controller.allProjects()) {
                ProjectDetailView(environment: environment, project: project, refreshTick: refreshTick)
            } else {
                ContentUnavailableView(
                    "Elige un proyecto",
                    systemImage: "square.stack.3d.up",
                    description: Text("Crea un proyecto y empieza una sesión desde la barra de menús.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if controller.isFocusing {
                    Text(DurationFormat.chronometer(controller.displayedElapsed))
                        .monospacedDigit()
                        .foregroundStyle(controller.phase == .pausedIdle ? .secondary : .primary)
                    Button("Detener") {
                        controller.stop(offerNotePrompt: true)
                    }
                } else if let project = selectedProject(controller.allProjects()) {
                    Button("Empezar foco") {
                        controller.start(project: project)
                    }
                    .keyboardShortcutReturn()
                }
                Button {
                    showNewProject = true
                } label: {
                    Label("Nuevo proyecto", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(environment: environment) { project in
                selectedProjectID = project.persistentModelID
                showNewProject = false
            }
        }
        .sheet(item: pendingNoteBinding) { item in
            SessionNoteSheet(
                projectName: item.session.project?.name ?? "Proyecto",
                note: $noteDraft,
                onSave: { text in
                    controller.attachNote(text, to: item.session)
                    noteDraft = ""
                },
                onSkip: {
                    controller.dismissNotePrompt()
                    noteDraft = ""
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .momentumPresentNewProjectSheet)) { _ in
            showNewProject = true
        }
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = controller.mostRecentlyUsedProject()?.persistentModelID
            }
        }
        .onChange(of: controller.displayedElapsed) { _, _ in
            refreshTick &+= 1
        }
        .onChange(of: controller.phase) { _, _ in
            refreshTick &+= 1
        }
    }

    private var pendingNoteBinding: Binding<NoteSheetItem?> {
        Binding(
            get: {
                controller.pendingNoteSession.map(NoteSheetItem.init)
            },
            set: { newValue in
                if newValue == nil {
                    controller.dismissNotePrompt()
                }
            }
        )
    }

    private func selectedProject(_ projects: [Project]) -> Project? {
        guard let selectedProjectID else { return projects.first }
        return projects.first(where: { $0.persistentModelID == selectedProjectID }) ?? projects.first
    }
}

private struct NoteSheetItem: Identifiable {
    let session: FocusSession
    var id: PersistentIdentifier { session.persistentModelID }
}

private extension View {
    @ViewBuilder
    func keyboardShortcutReturn() -> some View {
        self.keyboardShortcut(.defaultAction)
    }
}
