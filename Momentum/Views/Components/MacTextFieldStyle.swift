//
//  MacTextFieldStyle.swift
//  Momentum
//

import SwiftUI

#if os(macOS)
    private struct MacRoundedTextFieldModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor)),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1)),
                )
        }
    }

    extension View {
        func macRoundedTextFieldStyle() -> some View {
            modifier(MacRoundedTextFieldModifier())
        }
    }
#else
    extension View {
        func macRoundedTextFieldStyle() -> some View {
            self
        }
    }
#endif
