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
                Text(configurationHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = raycastIntegration.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                statusPills
            }

            if raycastIntegration.hasActiveToken {
                HStack(spacing: 8) {
                    Button(String(localized: "Desemparejar")) {
                        raycastIntegration.revokeTokens()
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!raycastIntegration.isEnabled)
            } else {
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
                        Text(pairingExpiryText(expiresAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button(raycastIntegration.pairingCode == nil ? String(localized: "Generar código") : String(localized: "Regenerar código")) {
                            raycastIntegration.refreshPairingCode()
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(!raycastIntegration.isEnabled)
                }
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
            return String(localized: "Integración desactivada.")
        }
        if raycastIntegration.isRunning {
            return String.localizedStringWithFormat(
                String(localized: "Servidor activo en 127.0.0.1:%lld."),
                raycastIntegration.port
            )
        }
        return String(localized: "Servidor detenido.")
    }

    private var configurationHintText: String {
        String.localizedStringWithFormat(
            String(localized: "Configura Raycast para usar 127.0.0.1:%lld."),
            raycastIntegration.port
        )
    }

    private func pairingExpiryText(_ expiresAt: Date) -> String {
        let localizedTime = expiresAt.formatted(date: .omitted, time: .shortened)
        return String.localizedStringWithFormat(
            String(localized: "Expira %@ · válido 10 min"),
            localizedTime
        )
    }

    @ViewBuilder
    private var statusPills: some View {
        HStack(spacing: 8) {
            if raycastIntegration.hasActiveToken {
                statusPill(text: String(localized: "Emparejado"), systemImage: "checkmark.circle.fill", style: .success)
            }
            if let message = raycastIntegration.statusMessage {
                statusPill(text: message.text, systemImage: message.systemImage, style: message.style)
            }
            if didCopyCode {
                statusPill(text: String(localized: "Código copiado"), systemImage: "doc.on.doc.fill", style: .info)
            }
        }
    }

    private func statusPill(text: String, systemImage: String, style: RaycastStatusMessage.Style) -> some View {
        let (foreground, background) = colors(for: style)
        return HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12, height: 12, alignment: .center)
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
            .frame(minHeight: 20, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
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
