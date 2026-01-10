//
//  ProjectWeeklySummaryChartView.swift
//  Momentum
//
//  Created by Miguel García González on 23/11/25.
//

import SwiftUI

enum ActivityRange: String, CaseIterable, Identifiable {
    case week
    case month
    case quarter
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Semana"
        case .month: return "Mes"
        case .quarter: return "Trimestre"
        case .year: return "Año"
        }
    }

    var interval: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: now)
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: now)
        case .quarter:
            let start = calendar.date(byAdding: .day, value: -90, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: now)
        case .year:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let start = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
            return DateInterval(start: start, end: now)
        }
    }

    var barWidth: CGFloat {
        switch self {
        case .week: return 28
        case .month: return 14
        case .quarter: return 18
        case .year: return 24
        }
    }
}

struct WeeklySummaryChartView: View {
    let project: Project
    @State private var hoveredDate: Date?
    @State private var range: ActivityRange = .month
    @State private var points: [DailySummaryPoint] = []
    @State private var buckets: [ActivityBucket] = []
    private let chartHeight: CGFloat = 120

    private var maxSeconds: TimeInterval {
        let values = buckets.map(\.seconds)
        return max(values.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            chartView
            footerView
        }
        .detailCardStyle(
            padding: 16,
            cornerRadius: 18,
            strokeOpacity: 0.08
        )
        .task(id: refreshKey) {
            refreshData()
        }
    }

    private var headerView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleBlock(alignment: .leading, textAlignment: .leading)
                Spacer()
                rangePicker
            }
            VStack(spacing: 10) {
                titleBlock(alignment: .center, textAlignment: .center)
                rangePicker
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func titleBlock(alignment: HorizontalAlignment, textAlignment: TextAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(titleText)
                .font(.headline)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rangePicker: some View {
        Picker("Rango", selection: $range) {
            ForEach(ActivityRange.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)
        .labelsHidden()
        .accessibilityLabel("Rango")
    }

    private var chartView: some View {
        ActivityBarsRow(
            project: project,
            buckets: buckets,
            chartHeight: chartHeight,
            maxSeconds: maxSeconds,
            hoveredDate: $hoveredDate,
            range: range
        )
    }

    private var footerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summariesTotalText)
                    .font(.subheadline.weight(.semibold))
                Text("\(activeDays) días activos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var summariesTotalText: String {
        let totalSeconds = points.reduce(0) { $0 + $1.seconds }
        return totalSeconds.hoursAndMinutesString
    }

    private var activeDays: Int {
        points.filter { $0.seconds > 0 }.count
    }

    private var titleText: String {
        switch range {
        case .week:
            return "Últimos 7 días"
        case .month:
            return "Últimos 30 días"
        case .quarter:
            return "Último trimestre"
        case .year:
            return "Último año"
        }
    }

    private var subtitleText: String {
        switch range {
        case .week:
            return "Actividad reciente y consistencia."
        case .month:
            return "Últimos 30 días en detalle."
        case .quarter:
            return "Semanas del último trimestre."
        case .year:
            return "Meses del último año."
        }
    }

    private func aggregate(
        points: [DailySummaryPoint],
        calendar: Calendar,
        by component: Calendar.Component
    ) -> [AggregatedBucket] {
        var totals: [Date: TimeInterval] = [:]
        for point in points {
            guard let bucketStart = calendar.dateInterval(of: component, for: point.date)?.start else { continue }
            totals[bucketStart, default: 0] += point.seconds
        }

        let bucketStarts = bucketDates(for: range, calendar: calendar, component: component)
        return bucketStarts.map { date in
            AggregatedBucket(date: date, seconds: totals[date, default: 0], totalCount: bucketStarts.count)
        }
    }

    private func refreshData() {
        let points = project.dailySummaries(in: range.interval)
        self.points = points
        buckets = buildBuckets(from: points)
    }

    private func buildBuckets(from points: [DailySummaryPoint]) -> [ActivityBucket] {
        let calendar = Calendar.current
        let locale = Locale.current
        switch range {
        case .week:
            return points.enumerated().map { _, point in
                ActivityBucket(
                    date: point.date,
                    seconds: point.seconds,
                    label: point.label.uppercased(),
                    showsLabel: true
                )
            }
        case .month:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "d"
            return points.enumerated().map { index, point in
                ActivityBucket(
                    date: point.date,
                    seconds: point.seconds,
                    label: formatter.string(from: point.date),
                    showsLabel: index % 5 == 0 || index == points.count - 1
                )
            }
        case .quarter:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "d/M"
            let aggregated = aggregate(points: points, calendar: calendar, by: .weekOfYear)
            return aggregated.enumerated().map { index, entry in
                ActivityBucket(
                    date: entry.date,
                    seconds: entry.seconds,
                    label: formatter.string(from: entry.date),
                    showsLabel: index == 0 || index == aggregated.count - 1 || index % 2 == 0
                )
            }
        case .year:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "MMM"
            let aggregated = aggregate(points: points, calendar: calendar, by: .month)
            return aggregated.map { entry in
                ActivityBucket(
                    date: entry.date,
                    seconds: entry.seconds,
                    label: formatter.string(from: entry.date).uppercased(),
                    showsLabel: true
                )
            }
        }
    }

    private func bucketDates(for range: ActivityRange, calendar: Calendar, component: Calendar.Component) -> [Date] {
        let interval = range.interval
        let start = calendar.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        var dates: [Date] = []
        var cursor = start
        let step: DateComponents
        switch component {
        case .weekOfYear:
            step = DateComponents(day: 7)
        case .month:
            step = DateComponents(month: 1)
        default:
            step = DateComponents(day: 1)
        }
        while cursor < interval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: step, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private struct AggregatedBucket {
        let date: Date
        let seconds: TimeInterval
        let totalCount: Int
    }

    private var refreshKey: String {
        "\(range.rawValue)-\(project.dailySummaries.count)"
    }
}

private struct ActivityBarsRow: View {
    let project: Project
    let buckets: [ActivityBucket]
    let chartHeight: CGFloat
    let maxSeconds: TimeInterval
    @Binding var hoveredDate: Date?
    let range: ActivityRange
    @State private var availableWidth: CGFloat = 0

    private let tooltipPadding: CGFloat = 12
    private let labelHeight: CGFloat = 18

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            let barWidth = barWidth(for: availableWidth)
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(Array(buckets.enumerated()), id: \.element.date) { index, summary in
                    ActivityBarView(
                        project: project,
                        summary: summary,
                        chartHeight: chartHeight,
                        maxSeconds: maxSeconds,
                        hoveredDate: $hoveredDate,
                        label: label(for: summary),
                        isToday: isToday(summary.date),
                        barWidth: barWidth,
                        labelHeight: labelHeight,
                        tooltipAlignment: tooltipAlignment(for: index)
                    )
                    .frame(width: barWidth)
                    .zIndex(hoveredDate == summary.date ? 1 : 0)
                }
            }
            .frame(minWidth: max(availableWidth, contentWidth(for: availableWidth)), alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, tooltipPadding)
        }
        .scrollDisabled(!needsScroll)
        .frame(height: chartHeight + labelHeight + tooltipPadding)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func label(for summary: ActivityBucket) -> String {
        if range == .week, isToday(summary.date) {
            return "HOY"
        }
        return summary.label.uppercased()
    }

    private var barSpacing: CGFloat {
        range == .week ? 12 : 10
    }

    private func barWidth(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return range.barWidth }
        let count = CGFloat(max(buckets.count, 1))
        let totalSpacing = barSpacing * (count - 1)
        let usable = max(availableWidth - totalSpacing - 8, range.barWidth * count)
        return max(range.barWidth, usable / count)
    }

    private func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(buckets.count, 1))
        let barWidth = barWidth(for: availableWidth)
        let totalSpacing = barSpacing * (count - 1)
        return barWidth * count + totalSpacing
    }

    private var needsScroll: Bool {
        contentWidth(for: availableWidth) > availableWidth
    }

    private func tooltipAlignment(for index: Int) -> Alignment {
        if index == 0 {
            return .topLeading
        }
        if index == buckets.count - 1 {
            return .topTrailing
        }
        return .top
    }
}

private struct ActivityBarView: View {
    let project: Project
    let summary: ActivityBucket
    let chartHeight: CGFloat
    let maxSeconds: TimeInterval
    @Binding var hoveredDate: Date?
    let label: String
    let isToday: Bool
    let barWidth: CGFloat
    let labelHeight: CGFloat
    let tooltipAlignment: Alignment

    var body: some View {
        VStack {
            barView
            labelView
        }
        .frame(maxWidth: .infinity)
    }

    private var barView: some View {
        VStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 6)
                .fill(barFillColor)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(barStrokeColor, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    if isHovered {
                        ChartTooltipView(text: summary.seconds.minutesOrHoursMinutesString)
                            .frame(width: barWidth, alignment: tooltipAlignment)
                            .offset(y: -8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(1)
                    }
                }
        }
        .zIndex(isHovered ? 1 : 0)
        .frame(height: chartHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredDate = hovering ? summary.date : nil
        }
        .animation(.easeInOut(duration: 0.12), value: hoveredDate)
    }

    private var labelView: some View {
        Group {
            if summary.showsLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.tail)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(height: labelHeight)
    }

    private var isHovered: Bool {
        hoveredDate == summary.date
    }

    private var barFillColor: Color {
        project.color.opacity(summary.seconds == 0 ? 0.12 : 0.75)
    }

    private var barStrokeColor: Color {
        isToday ? project.color.opacity(0.7) : .clear
    }

    private var height: CGFloat {
        let ratio = summary.seconds / max(maxSeconds, 1)
        return max(12, CGFloat(ratio) * chartHeight)
    }
}

private struct ActivityBucket: Identifiable {
    let date: Date
    let seconds: TimeInterval
    let label: String
    let showsLabel: Bool

    var id: Date { date }
}
