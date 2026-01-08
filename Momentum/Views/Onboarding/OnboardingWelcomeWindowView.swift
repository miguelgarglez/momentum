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

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Bienvenido a Momentum")
                    .font(.title2.weight(.semibold))
                Text("Crea tu primer proyecto y empieza a convertir tu tiempo en progreso visible.")
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: 12) {
                Button("Saltar") {
                    onboardingState.markWelcomeSeen()
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
                        OnboardingUserInfoKey.startTracking: true
                    ]
                )
                dismiss()
            }
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
