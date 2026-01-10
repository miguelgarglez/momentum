//
//  RemovableChip.swift
//  Momentum
//
//  Created by Codex on 10/01/26.
//

import SwiftUI

struct RemovableChip<Leading: View>: View {
    let title: String
    let leading: Leading
    let removeAccessibilityLabel: String?
    let showsLeading: Bool
    let showsRemoveButton: Bool
    let onRemove: () -> Void

    init(
        title: String,
        removeAccessibilityLabel: String? = nil,
        showsLeading: Bool = true,
        showsRemoveButton: Bool = true,
        @ViewBuilder leading: () -> Leading,
        onRemove: @escaping () -> Void,
    ) {
        self.title = title
        self.leading = leading()
        self.removeAccessibilityLabel = removeAccessibilityLabel
        self.showsLeading = showsLeading
        self.showsRemoveButton = showsRemoveButton
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsLeading {
                leading
            }
            Text(title)
                .font(.caption)
                .lineLimit(1)
            if showsRemoveButton {
                if let label = removeAccessibilityLabel {
                    removeButton
                        .accessibilityLabel(label)
                } else {
                    removeButton
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
