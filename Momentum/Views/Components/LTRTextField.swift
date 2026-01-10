//
//  LTRTextField.swift
//  Momentum
//
//  Created by Codex on 11/03/24.
//

import SwiftUI

#if os(macOS)
    import AppKit

    struct LTRTextField: NSViewRepresentable {
        final class Coordinator: NSObject, NSTextFieldDelegate {
            @Binding var text: String

            init(text: Binding<String>) {
                _text = text
            }

            func controlTextDidChange(_ obj: Notification) {
                guard let field = obj.object as? NSTextField else { return }
                text = field.stringValue
            }
        }

        enum Style {
            case plain
            case roundedBorder
        }

        @Binding var text: String
        var placeholder: String = ""
        var font: NSFont = .preferredFont(forTextStyle: .body)
        var style: Style = .plain
        var allowsMultiline: Bool = false
        var accessibilityIdentifier: String? = nil

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        func makeNSView(context: Context) -> NSTextField {
            let field = NSTextField(string: text)
            field.placeholderString = placeholder
            field.alignment = .left
            field.baseWritingDirection = .leftToRight
            field.delegate = context.coordinator
            field.font = font
            configureLineMode(for: field)
            apply(style: style, to: field)
            field.setAccessibilityIdentifier(accessibilityIdentifier)
            return field
        }

        func updateNSView(_ nsView: NSTextField, context _: Context) {
            if nsView.stringValue != text {
                nsView.stringValue = text
            }
            nsView.placeholderString = placeholder
            nsView.alignment = .left
            nsView.baseWritingDirection = .leftToRight
            if nsView.font != font {
                nsView.font = font
            }
            configureLineMode(for: nsView)
            apply(style: style, to: nsView)
            if nsView.accessibilityIdentifier() != accessibilityIdentifier {
                nsView.setAccessibilityIdentifier(accessibilityIdentifier)
            }
        }

        private func configureLineMode(for field: NSTextField) {
            field.usesSingleLineMode = !allowsMultiline
            field.maximumNumberOfLines = allowsMultiline ? 0 : 1
            field.lineBreakMode = allowsMultiline ? .byWordWrapping : .byTruncatingTail
        }

        private func apply(style: Style, to field: NSTextField) {
            switch style {
            case .plain:
                field.isBezeled = false
                field.isBordered = false
                field.drawsBackground = false
                field.focusRingType = .none
            case .roundedBorder:
                field.isBezeled = true
                field.isBordered = true
                field.bezelStyle = .roundedBezel
                field.drawsBackground = false
                field.focusRingType = .default
            }
        }
    }
#endif
