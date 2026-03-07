import SwiftUI

enum FormSheetMetrics {
    static let standardWidth: CGFloat = 580
    static let standardHeight: CGFloat = 488
    static let contentPadding: CGFloat = 20
}

enum FormCardProminence {
    case regular
    case emphasized
    case inset
}

private struct FormSheetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct FormCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let prominence: FormCardProminence
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
    }

    private var backgroundFill: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(solidBackgroundColor)
        }

        switch prominence {
        case .regular:
            return AnyShapeStyle(.ultraThinMaterial)
        case .emphasized:
            return AnyShapeStyle(.thinMaterial)
        case .inset:
            return AnyShapeStyle(Color.secondary.opacity(0.10))
        }
    }

    private var solidBackgroundColor: Color {
        switch prominence {
        case .regular:
            return Color(nsColor: .controlBackgroundColor)
        case .emphasized:
            return Color(nsColor: .underPageBackgroundColor)
        case .inset:
            return Color.secondary.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .regular:
            return Color.primary.opacity(0.08)
        case .emphasized:
            return Color.primary.opacity(0.10)
        case .inset:
            return Color.primary.opacity(0.07)
        }
    }

    private var shadowColor: Color {
        switch prominence {
        case .regular:
            return .black.opacity(0.06)
        case .emphasized:
            return .black.opacity(0.08)
        case .inset:
            return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch prominence {
        case .regular:
            return 12
        case .emphasized:
            return 18
        case .inset:
            return 0
        }
    }

    private var shadowYOffset: CGFloat {
        switch prominence {
        case .regular:
            return 4
        case .emphasized:
            return 8
        case .inset:
            return 0
        }
    }
}

private struct FormSectionHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private struct FormSupportCopyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FormKeyValueRowModifier: ViewModifier {
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .font(emphasized ? .headline : .body)
            .foregroundStyle(emphasized ? .primary : .secondary)
    }
}

extension View {
    func formSheetBackgroundStyle() -> some View {
        modifier(FormSheetBackgroundModifier())
    }

    func formCardStyle(
        prominence: FormCardProminence = .regular,
        padding: CGFloat = 18,
        cornerRadius: CGFloat = 20
    ) -> some View {
        modifier(FormCardModifier(prominence: prominence, padding: padding, cornerRadius: cornerRadius))
    }

    func formSectionHeaderStyle() -> some View {
        modifier(FormSectionHeaderModifier())
    }

    func formSupportCopyStyle() -> some View {
        modifier(FormSupportCopyModifier())
    }

    func formKeyValueStyle(emphasized: Bool = false) -> some View {
        modifier(FormKeyValueRowModifier(emphasized: emphasized))
    }
}

struct FormInlineStatusRow: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
