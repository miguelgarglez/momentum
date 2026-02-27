//
//  ToastView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case error
        case info
    }

    let id = UUID()
    let message: String
    let style: Style
}

struct ToastView: View {
    let message: String
    let style: ToastMessage.Style

    private var iconName: String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch style {
        case .success: .green
        case .error: .orange
        case .info: .blue
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(tint)
            Text(message)
                .font(.callout)
                .bold()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 10, x: 0, y: 4)
    }
}
