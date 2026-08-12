import SwiftUI

struct SessionNoteSheet: View {
    let projectName: String
    @Binding var note: String
    var onSave: (String) -> Void
    var onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("¿Qué hiciste?")
                .font(.title3.weight(.semibold))
            Text("Sesión en \(projectName). Opcional, máx. 80 caracteres.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Nota breve", text: $note)
                .textFieldStyle(.roundedBorder)
                .onChange(of: note) { _, newValue in
                    if newValue.count > 80 {
                        note = String(newValue.prefix(80))
                    }
                }
                .onSubmit(save)

            HStack {
                Text("\(note.count)/80")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Omitir") {
                    onSkip()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Guardar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func save() {
        onSave(note)
        dismiss()
    }
}
