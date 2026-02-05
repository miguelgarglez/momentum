import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct SettingsRaycastSectionView: View {
    @Binding var draft: TrackerSettingsDraft
    @EnvironmentObject private var raycastIntegration: RaycastIntegrationManager
    @State private var didCopyCode = false

    var body: some View {
        Section {
            Toggle("Habilitar integración con Raycast", isOn: $draft.isRaycastIntegrationEnabled)

            if draft.isRaycastIntegrationEnabled != raycastIntegration.isEnabled {
                Text("Guarda los cambios para aplicar la integración.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(statusText)
                    .font(.subheadline)
                Text("Configura Raycast para usar 127.0.0.1:\(raycastIntegration.port).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = raycastIntegration.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                statusPills
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Código de emparejamiento")
                    .font(.subheadline)
                if let code = raycastIntegration.pairingCode {
                    HStack(spacing: 12) {
                        Text(code)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Button("Copiar") {
                            copyToPasteboard(code)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Genera un código para emparejar Raycast.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let expiresAt = raycastIntegration.pairingExpiresAt {
                    Text("Expira \(expiresAt, style: .time) · válido 10 min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button(raycastIntegration.pairingCode == nil ? "Generar código" : "Regenerar código") {
                        raycastIntegration.refreshPairingCode()
                    }
                    .buttonStyle(.bordered)

                    Button("Revocar tokens") {
                        raycastIntegration.revokeTokens()
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!raycastIntegration.isEnabled)
            }
        } header: {
            SettingsSectionHeader(
                "Raycast Extension",
                subtitle: "Activa la integración local para controlar Momentum desde Raycast.",
            )
        }
    }

    private var statusText: String {
        if !raycastIntegration.isEnabled {
            return "Integración desactivada."
        }
        if raycastIntegration.isRunning {
            return "Servidor activo en 127.0.0.1:\(raycastIntegration.port)."
        }
        return "Servidor detenido."
    }

    @ViewBuilder
    private var statusPills: some View {
        HStack(spacing: 8) {
            if raycastIntegration.hasActiveToken {
                statusPill(text: "Emparejado", systemImage: "checkmark.circle.fill", style: .success)
            }
            if let message = raycastIntegration.statusMessage {
                statusPill(text: message.text, systemImage: message.systemImage, style: message.style)
            }
            if didCopyCode {
                statusPill(text: "Código copiado", systemImage: "doc.on.doc.fill", style: .info)
            }
        }
    }

    private func statusPill(text: String, systemImage: String, style: RaycastStatusMessage.Style) -> some View {
        let (foreground, background) = colors(for: style)
        return Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private func colors(for style: RaycastStatusMessage.Style) -> (Color, Color) {
        switch style {
        case .success:
            return (.green, Color.green.opacity(0.18))
        case .warning:
            return (.orange, Color.orange.opacity(0.18))
        case .info:
            return (.secondary, Color.secondary.opacity(0.12))
        }
    }

    private func copyToPasteboard(_ code: String) {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(code, forType: .string)
        #endif
        didCopyCode = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            didCopyCode = false
        }
    }
}

#Preview {
    SettingsRaycastSectionView(draft: .constant(TrackerSettingsDraft()))
        .environmentObject(RaycastIntegrationManager(settings: TrackerSettings()))
}
