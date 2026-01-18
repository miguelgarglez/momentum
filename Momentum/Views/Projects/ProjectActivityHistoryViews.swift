//
//  ProjectActivityHistoryViews.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI

struct ActivityHistorySectionView: View {
    let project: Project
    let refreshToken: Int
    @State private var selectedYear: Int = Calendar.current.component(.year, from: .now)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heatmap anual")
                    .font(.headline)
                Text("Distribución diaria de tu actividad por año.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ActivityHeatmapView(project: project, refreshToken: refreshToken, selectedYear: $selectedYear)
        }
        .detailCardStyle(
            padding: 16,
            cornerRadius: 18,
            strokeOpacity: 0.08,
        )
    }
}

struct ActivityHeatmapView: View {
    let project: Project
    let refreshToken: Int
    @Binding var selectedYear: Int
    @State private var hoveredDay: Date?
    @State private var days: [HeatmapDay] = []
    @State private var weeks: [[HeatmapDay]] = []
    @State private var monthLabels: [String?] = []
    @State private var thresholds: [TimeInterval] = [0, 0, 0]
    @State private var availableYears: [Int] = []

    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heatmap")
                        .font(.subheadline.weight(.semibold))
                    Text(yearTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Año", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        VStack(spacing: spacing) {
                            monthLabelView(for: weekIndex)
                            VStack(spacing: spacing) {
                                ForEach(weeks[weekIndex]) { day in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color(for: day))
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(
                                                    hoveredDay == day.date && day.seconds > 0 ? project.color.opacity(0.7) : .clear,
                                                    lineWidth: 1,
                                                ),
                                        )
                                        .overlay(alignment: .top) {
                                            if hoveredDay == day.date, day.isInRange, day.seconds > 0 {
                                                ChartTooltipView(text: day.seconds.minutesOrHoursMinutesString)
                                                    .offset(x: tooltipOffset(for: weekIndex), y: -8)
                                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onHover { hovering in
                                            hoveredDay = hovering ? day.date : nil
                                        }
                                        .animation(.easeInOut(duration: 0.12), value: hoveredDay)
                                }
                            }
                        }
                        .frame(width: cellSize)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            HStack(spacing: 6) {
                Text("Menos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0 ..< 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: index))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("Más")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: refreshKey) { refreshDays() }
    }

    private var yearTitle: String {
        String(selectedYear)
    }

    private func color(for day: HeatmapDay) -> Color {
        guard day.isInRange else {
            return Color.primary.opacity(0.05)
        }
        return color(for: intensity(for: day.seconds))
    }

    private func color(for intensity: Int) -> Color {
        switch intensity {
        case 0: Color.primary.opacity(0.08)
        case 1: project.color.opacity(0.25)
        case 2: project.color.opacity(0.45)
        case 3: project.color.opacity(0.65)
        default: project.color.opacity(0.85)
        }
    }

    private func intensity(for seconds: TimeInterval) -> Int {
        HeatmapIntensityCalculator.intensity(for: seconds, thresholds: thresholds)
    }

    private func refreshDays() {
        updateAvailableYears()
        ensureSelectedYearIsAvailable()
        let interval = yearInterval(for: selectedYear)
        let calendar = Calendar.current
        let rangeStart = DailySummary.normalize(interval.start)
        let rangeEnd = DailySummary.normalize(interval.end)
        let gridStart = startOfWeek(for: rangeStart, calendar: calendar)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: rangeEnd) ?? rangeEnd
        let gridEnd = calendar.date(byAdding: .day, value: 7, to: startOfWeek(for: lastDay, calendar: calendar)) ?? rangeEnd

        let points = project.dailySummaries(in: interval)
        let totals = Dictionary(uniqueKeysWithValues: points.map { ($0.date, $0.seconds) })

        var days: [HeatmapDay] = []
        var cursor = gridStart
        while cursor < gridEnd {
            let isInRange = cursor >= rangeStart && cursor < rangeEnd
            let seconds = isInRange ? totals[cursor, default: 0] : 0
            days.append(HeatmapDay(date: cursor, seconds: seconds, isInRange: isInRange))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }

        self.days = days
        weeks = buildWeeks(from: days)
        monthLabels = buildMonthLabels(from: weeks)
        let values = days.filter { $0.isInRange && $0.seconds > 0 }.map(\.seconds)
        thresholds = HeatmapIntensityCalculator.thresholds(for: values)
    }

    private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: calendar.startOfDay(for: date)) ?? date
    }

    private var refreshKey: String {
        "\(selectedYear)-\(refreshToken)"
    }

    private func yearInterval(for year: Int) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func ensureSelectedYearIsAvailable() {
        guard !availableYears.contains(selectedYear) else { return }
        selectedYear = availableYears.first ?? Calendar.current.component(.year, from: .now)
    }

    private func tooltipOffset(for weekIndex: Int) -> CGFloat {
        let lastIndex = max(weeks.count - 1, 0)
        if weekIndex == 0 { return 12 }
        if weekIndex == lastIndex { return -12 }
        return 0
    }

    private func monthLabelView(for weekIndex: Int) -> some View {
        let label = monthLabel(for: weekIndex)
        return Group {
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(height: cellSize)
    }

    private func monthLabel(for weekIndex: Int) -> String? {
        guard weekIndex < monthLabels.count else { return nil }
        return monthLabels[weekIndex]
    }

    private func updateAvailableYears() {
        let calendar = Calendar.current
        var years: Set<Int> = []
        if !project.dailySummaries.isEmpty {
            for summary in project.dailySummaries {
                years.insert(calendar.component(.year, from: summary.date))
            }
        } else {
            for session in project.sessions {
                years.insert(calendar.component(.year, from: session.startDate))
                years.insert(calendar.component(.year, from: session.endDate))
            }
        }
        if years.isEmpty {
            years.insert(calendar.component(.year, from: .now))
        }
        availableYears = years.sorted(by: >)
    }

    private func buildWeeks(from days: [HeatmapDay]) -> [[HeatmapDay]] {
        stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index ..< min(index + 7, days.count)])
        }
    }

    private func buildMonthLabels(from weeks: [[HeatmapDay]]) -> [String?] {
        guard !weeks.isEmpty else { return [] }
        let calendar = Calendar.current
        let formatter = Self.monthFormatter
        formatter.locale = Locale.current
        return weeks.map { week in
            for day in week where day.isInRange {
                if calendar.component(.day, from: day.date) == 1 {
                    return formatter.string(from: day.date).uppercased()
                }
            }
            return nil
        }
    }
}

private extension ActivityHeatmapView {
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

private struct HeatmapDay: Identifiable {
    let date: Date
    let seconds: TimeInterval
    let isInRange: Bool

    var id: Date { date }
}
