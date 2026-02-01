//
//  SFSymbolPickerView.swift
//  Momentum
//
//  Created by Codex on 01/02/26.
//

import SwiftUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct SFSymbolPickerView: View {
    let title: String
    let placeholder: String
    let accessibilityIdentifier: String
    @Binding var selection: String
    let onDismiss: (() -> Void)?

    @State private var searchText: String = ""
    @State private var selectedCategoryID: String = "recommended"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            searchField

            categorySelector

            selectedPreview

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        symbolCell(for: symbol)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 160, maxHeight: 240)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .onExitCommand {
            onDismiss?()
        }
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(macOS)
            LTRTextField(
                text: $searchText,
                placeholder: placeholder,
                accessibilityIdentifier: "\(accessibilityIdentifier)-search"
            )
            .macRoundedTextFieldStyle()
        #else
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("\(accessibilityIdentifier)-search")
        #endif
    }

    private var selectedPreview: some View {
        HStack(spacing: 10) {
            Image(systemName: resolvedSelection)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(resolvedSelection)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(id: "recommended", title: "Recomendados")
                categoryButton(id: "all", title: "Todos")
                ForEach(SymbolCatalog.categories) { category in
                    categoryButton(id: category.id, title: category.title)
                }
            }
        }
    }

    private func categoryButton(id: String, title: String) -> some View {
        Button {
            selectedCategoryID = id
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selectedCategoryID == id ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private var filteredSymbols: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let baseSymbols: [String]
        switch selectedCategoryID {
        case "recommended":
            baseSymbols = SymbolCatalog.recommendedSymbols
        case "all":
            baseSymbols = SymbolCatalog.symbols
        default:
            baseSymbols = SymbolCatalog.categories.first { $0.id == selectedCategoryID }?.symbols ?? SymbolCatalog.symbols
        }

        guard !query.isEmpty else { return baseSymbols }
        let tokens = query.split(separator: " ").map(String.init)
        return baseSymbols.filter { symbol in
            let name = symbol.lowercased()
            return tokens.allSatisfy { name.contains($0) }
        }
    }

    private var resolvedSelection: String {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "questionmark" }
        return isValidSymbol(trimmed) ? trimmed : "questionmark"
    }

    @ViewBuilder
    private func symbolCell(for symbol: String) -> some View {
        Button {
            selection = symbol
            onDismiss?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selection == symbol ? selectionFillColor : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selection == symbol ? selectionStrokeColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        #if os(macOS)
            .help(symbol)
        #endif
    }

    private var selectionFillColor: Color {
        #if os(macOS)
            return Color(nsColor: .selectedControlColor).opacity(0.15)
        #else
            return Color.accentColor.opacity(0.15)
        #endif
    }

    private var selectionStrokeColor: Color {
        #if os(macOS)
            return Color(nsColor: .selectedControlColor)
        #else
            return Color.accentColor
        #endif
    }

    private func isValidSymbol(_ name: String) -> Bool {
        #if os(macOS)
            return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
            return UIImage(systemName: name) != nil
        #endif
    }
}
