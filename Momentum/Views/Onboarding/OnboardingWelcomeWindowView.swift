//
//  OnboardingWelcomeWindowView.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct OnboardingWelcomeWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var onboardingState: OnboardingState
    @State private var showQuickCreate = false

    private let symbols = [
        "infinity.circle",
        "chart.bar.xaxis",
        "clock.arrow.trianglehead.2.counterclockwise.rotate.90",
        "chart.line.uptrend.xyaxis",
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                AnimatedSymbolSequenceView(
                    symbols: symbols,
                    size: 40,
                    frameSize: 44
                )
                Text("Bienvenido a Momentum")
                    .font(.title2.weight(.semibold))
                Text("Crea tu primer proyecto y empieza a convertir tu tiempo en progreso visible.")
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
            }

            VStack(alignment: .leading, spacing: 8) {
                onboardingBullet(icon: "infinity.circle", text: "Mantén el ritmo con seguimiento continuo y sin fricción.")
                onboardingBullet(icon: "chart.bar.xaxis", text: "Visualiza cómo distribuyes tu tiempo entre proyectos.")
                onboardingBullet(icon: "clock.arrow.trianglehead.2.counterclockwise.rotate.90", text: "Recupera sesiones y evita pérdidas de tiempo.")
                onboardingBullet(icon: "chart.line.uptrend.xyaxis", text: "Convierte el trabajo en progreso visible y tendencias claras.")
            }
            .frame(maxWidth: 360, alignment: .leading)

            HStack(spacing: 12) {
                Button("Saltar") {
                    onboardingState.markWelcomeSeen()
                    #if os(macOS)
                        NotificationCenter.default.post(name: .statusItemShowApp, object: nil)
                    #endif
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Crear proyecto") {
                    showQuickCreate = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(minWidth: 420, maxWidth: 480)
        .onAppear {
            onboardingState.markWelcomeSeen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingProjectCreated)) { _ in
            showQuickCreate = false
            #if os(macOS)
                closeWelcomeWindow()
            #endif
            dismiss()
        }
        .sheet(isPresented: $showQuickCreate) {
            OnboardingQuickProjectView { project in
                NotificationCenter.default.post(
                    name: .onboardingProjectCreated,
                    object: nil,
                    userInfo: [
                        OnboardingUserInfoKey.projectID: project.persistentModelID,
                        OnboardingUserInfoKey.startTracking: true,
                    ],
                )
                #if os(macOS)
                    NotificationCenter.default.post(name: .statusItemShowApp, object: nil)
                #endif
                dismiss()
            }
        }
    }

    private func onboardingBullet(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #if os(macOS)
        private func closeWelcomeWindow() {
            if let window = NSApp.keyWindow {
                window.close()
                return
            }
            for window in NSApp.windows where window.isVisible {
                window.close()
                break
            }
        }
    #endif
}
