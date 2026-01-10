import Foundation

enum HeatmapIntensityCalculator {
    nonisolated static func thresholds(for values: [TimeInterval]) -> [TimeInterval] {
        let sortedValues = values.sorted()
        if sortedValues.isEmpty {
            return []
        }
        if sortedValues.count == 1 {
            return [sortedValues[0], sortedValues[0], sortedValues[0]]
        }
        return [
            percentile(0.25, in: sortedValues),
            percentile(0.5, in: sortedValues),
            percentile(0.75, in: sortedValues),
        ]
    }

    nonisolated static func intensity(for seconds: TimeInterval, thresholds: [TimeInterval]) -> Int {
        guard seconds > 0 else { return 0 }
        if thresholds.count < 3 { return 1 }
        if seconds <= thresholds[0] { return 1 }
        if seconds <= thresholds[1] { return 2 }
        if seconds <= thresholds[2] { return 3 }
        return 4
    }

    nonisolated private static func percentile(_ percentile: Double, in values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let index = Int(round(Double(values.count - 1) * percentile))
        return values[min(max(index, 0), values.count - 1)]
    }
}
