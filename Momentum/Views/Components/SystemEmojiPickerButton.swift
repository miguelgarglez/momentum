//
//  SystemEmojiPickerButton.swift
//  Momentum
//
//  Created by Codex on 01/02/26.
//

import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct SystemEmojiPickerButton: View {
    let title: String
    let accessibilityIdentifier: String
    @Binding var selection: String

    @State private var buffer: String = ""
    @FocusState private var isFocused: Bool

    #if os(macOS)
        private let bufferSize = CGSize(width: 1, height: 1)
        private let bufferOpacity = 0.01
        private let bufferOffset = CGSize(width: 0, height: -4)
    #endif

    var body: some View {
        Button {
            openSystemEmojiPicker()
        } label: {
            Label(title, systemImage: "face.smiling")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(accessibilityIdentifier)
        #if os(macOS)
            .overlay(alignment: .top) {
                TextField("", text: $buffer)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .frame(width: bufferSize.width, height: bufferSize.height)
                    .opacity(bufferOpacity)
                    .offset(x: bufferOffset.width, y: bufferOffset.height)
                    .allowsHitTesting(false)
                    .onChange(of: buffer) { _, newValue in
                        handleEmojiInput(newValue)
                    }
            }
        #endif
    }

    #if os(macOS)
        private func openSystemEmojiPicker() {
            isFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.orderFrontCharacterPalette(nil)
            }
        }

        private func handleEmojiInput(_ value: String) {
            guard let emoji = EmojiDetector.firstEmoji(in: value) else { return }
            selection = emoji
            buffer = ""
        }
    #else
        private func openSystemEmojiPicker() {}
    #endif
}
