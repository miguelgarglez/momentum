import XCTest
@testable import Momentum

final class HeatmapIntensityCalculatorTests: XCTestCase {
    func testThresholdsEmptyWhenNoValues() {
        let thresholds = HeatmapIntensityCalculator.thresholds(for: [])
        XCTAssertEqual(thresholds, [])
    }

    func testThresholdsRepeatSingleValue() {
        let thresholds = HeatmapIntensityCalculator.thresholds(for: [120])
        XCTAssertEqual(thresholds, [120, 120, 120])
    }

    func testIntensityUsesFallbackWhenNoThresholds() {
        let intensity = HeatmapIntensityCalculator.intensity(for: 60, thresholds: [])
        XCTAssertEqual(intensity, 1)
    }

    func testIntensityBucketsByThresholds() {
        let thresholds = HeatmapIntensityCalculator.thresholds(for: [10, 20, 30, 40])
        XCTAssertEqual(thresholds, [20, 30, 30])
        XCTAssertEqual(HeatmapIntensityCalculator.intensity(for: 5, thresholds: thresholds), 1)
        XCTAssertEqual(HeatmapIntensityCalculator.intensity(for: 25, thresholds: thresholds), 2)
        XCTAssertEqual(HeatmapIntensityCalculator.intensity(for: 35, thresholds: thresholds), 4)
    }
}
