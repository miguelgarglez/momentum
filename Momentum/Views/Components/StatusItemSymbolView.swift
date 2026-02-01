#if os(macOS)
    import SwiftUI

    @MainActor
    final class StatusItemSymbolViewModel: ObservableObject {
        @Published var isConflicting: Bool = false
        @Published var isManualTrackingActive: Bool = false
        @Published var conflictChangeToken: Int = 0
    }

    struct StatusItemSymbolView: View {
        @ObservedObject var model: StatusItemSymbolViewModel
        @State private var appearToken: Int = 0

        private var ringColor: Color {
            if model.isManualTrackingActive {
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
                baseView.symbolEffect(.breathe, options: .repeating, value: model.isManualTrackingActive)
            } else {
                baseView
            }
        }
    }
#endif
