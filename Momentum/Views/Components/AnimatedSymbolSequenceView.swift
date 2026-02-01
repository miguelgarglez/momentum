//
//  AnimatedSymbolSequenceView.swift
//  Momentum
//
//  Created by Codex on 01/02/26.
//

import SwiftUI

struct AnimatedSymbolSequenceView: View {
    let symbols: [String]
    let size: CGFloat
    let frameSize: CGFloat
    let interval: Duration
    let animationDuration: Double
    let foregroundStyle: AnyShapeStyle

    @State private var symbolIndex = 0
    @State private var symbolAnimationTask: Task<Void, Never>?
    @State private var outgoingSymbol: String?
    @State private var outgoingSymbolClearTask: Task<Void, Never>?

    init(
        symbols: [String],
        size: CGFloat = 40,
        frameSize: CGFloat? = nil,
        interval: Duration = .seconds(2.4),
        animationDuration: Double = 0.6,
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(.secondary)
    ) {
        self.symbols = symbols
        self.size = size
        self.frameSize = frameSize ?? (size + 4)
        self.interval = interval
        self.animationDuration = animationDuration
        self.foregroundStyle = foregroundStyle
    }

    var body: some View {
        ZStack {
            let image = Image(systemName: symbols[symbolIndex])
                .font(.system(size: size))
                .foregroundStyle(foregroundStyle)
                .animation(.snappy(duration: animationDuration), value: symbolIndex)

            if #available(macOS 26.0, *) {
                image
                    .contentTransition(
                        .symbolEffect(
                            .replace.magic(fallback: .downUp.byLayer),
                            options: .nonRepeating
                        )
                    )
            } else {
                image
                    .contentTransition(
                        .symbolEffect(.replace.downUp.byLayer, options: .nonRepeating)
                    )
            }

            if #available(macOS 26.0, *), let outgoingSymbol {
                Image(systemName: outgoingSymbol)
                    .font(.system(size: size))
                    .foregroundStyle(foregroundStyle)
                    .symbolEffect(.drawOff.byLayer, options: .nonRepeating)
            }
        }
        .frame(width: frameSize, height: frameSize, alignment: .center)
        .onAppear {
            startSymbolAnimation()
        }
        .onDisappear {
            symbolAnimationTask?.cancel()
            symbolAnimationTask = nil
            outgoingSymbolClearTask?.cancel()
            outgoingSymbolClearTask = nil
        }
    }

    private func startSymbolAnimation() {
        symbolAnimationTask?.cancel()
        symbolAnimationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                let previousIndex = symbolIndex
                withAnimation(.snappy(duration: animationDuration)) {
                    symbolIndex = (symbolIndex + 1) % symbols.count
                }
                setOutgoingSymbol(symbols[previousIndex])
            }
        }
    }

    private func setOutgoingSymbol(_ symbol: String) {
        let isInfinity = symbol == "infinity.circle"
        let clearDelay: Duration = isInfinity ? .seconds(1.05) : .seconds(0.7)
        outgoingSymbol = symbol
        outgoingSymbolClearTask?.cancel()
        outgoingSymbolClearTask = Task { @MainActor in
            try? await Task.sleep(for: clearDelay)
            if !Task.isCancelled {
                outgoingSymbol = nil
            }
        }
    }
}
