//
//  ProjectIconPickerPopoverView.swift
//  Momentum
//
//  Created by Codex on 01/02/26.
//

import SwiftUI

struct ProjectIconPickerPopoverView: View {
    @Binding var selection: String
    let onDismiss: (() -> Void)?

    init(selection: Binding<String>, onDismiss: (() -> Void)? = nil) {
        _selection = selection
        self.onDismiss = onDismiss
    }

    var body: some View {
        SFSymbolPickerView(
            title: String(localized: "Iconos del sistema"),
            placeholder: String(localized: "Buscar iconos"),
            accessibilityIdentifier: "project-icon-symbol-picker",
            selection: $selection,
            onDismiss: onDismiss
        )
        .frame(width: 360, height: 360)
        .padding()
    }
}
