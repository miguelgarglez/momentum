#if os(macOS)
    import SwiftUI

    @MainActor
    final class StatusItemSymbolViewModel: ObservableObject {
        @Published var isConflicting: Bool = false
        @Published var isProjectTrackingActive: Bool = false
        @Published var conflictChangeToken: Int = 0
    }

    struct StatusItemSymbolView: View {
        @ObservedObject var model: StatusItemSymbolViewModel
        @State private var appearToken: Int = 0
        @State private var fallbackPulseIsExpanded: Bool = false

        private var ringColor: Color {
            if model.isProjectTrackingActive {
                return Color(nsColor: .systemTeal)
            }
            if model.isConflicting {
                return Color(nsColor: .systemOrange)
            }
            return Color(nsColor: .tertiaryLabelColor)
        }

        private var infinityColor: Color {
            Color(nsColor: .labelColor)
        }

        var body: some View {
            let baseView = Image(systemName: "infinity.circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(infinityColor, ringColor)
                .font(.system(size: 16, weight: .regular))
                .contentTransition(.symbolEffect(.replace.downUp.byLayer, options: .nonRepeating))
                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: appearToken)
                .id(model.conflictChangeToken)
                .accessibilityLabel("Momentum")
                .onAppear {
                    appearToken += 1
                }

            if #available(macOS 15.0, *) {
                baseView.symbolEffect(.breathe, options: .repeating, isActive: model.isProjectTrackingActive)
            } else {
                baseView
                    .scaleEffect(fallbackPulseScale)
                    .opacity(fallbackPulseOpacity)
                    .onAppear {
                        updateFallbackPulseAnimation(isActive: model.isProjectTrackingActive)
                    }
                    .onChange(of: model.isProjectTrackingActive) {
                        updateFallbackPulseAnimation(isActive: model.isProjectTrackingActive)
                    }
            }
        }

        private var fallbackPulseScale: CGFloat {
            guard model.isProjectTrackingActive else { return 1.0 }
            return fallbackPulseIsExpanded ? 1.06 : 0.94
        }

        private var fallbackPulseOpacity: Double {
            guard model.isProjectTrackingActive else { return 1.0 }
            return fallbackPulseIsExpanded ? 1.0 : 0.8
        }

        private func updateFallbackPulseAnimation(isActive: Bool) {
            if isActive {
                fallbackPulseIsExpanded = false
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    fallbackPulseIsExpanded = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    fallbackPulseIsExpanded = false
                }
            }
        }
    }
#endif
