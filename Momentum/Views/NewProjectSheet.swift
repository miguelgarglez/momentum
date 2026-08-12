import SwiftUI

struct NewProjectSheet: View {
    let environment: AppEnvironment
    var onCreated: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = ProjectColorPalette.defaultHex

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nuevo proyecto")
                .font(.title2.weight(.semibold))

            TextField("Nombre", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            HStack(spacing: 8) {
                ForEach(ProjectColorPalette.presets, id: \.self) { hex in
                    Circle()
                        .fill(ProjectColor.color(from: hex))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if colorHex == hex {
                                Circle().strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                        .onTapGesture { colorHex = hex }
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Crear") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let project = environment.sessionController.createProject(name: trimmed, colorHex: colorHex)
        onCreated(project)
        dismiss()
    }
}
