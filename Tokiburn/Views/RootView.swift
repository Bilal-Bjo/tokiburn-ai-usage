import AppKit
import Charts
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showingEstimateInfo = false

    var body: some View {
        ZStack {
            TokiburnTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    hairline
                    hero
                    trend
                    hairline
                    activity
                    footer
                }
                .padding(.horizontal, 34)
                .padding(.top, 18)
                .padding(.bottom, 20)
                .frame(maxWidth: 1_260)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(TokiburnTheme.ink)
        .onAppear {
            if let icon = NSImage(named: "BrandIcon") {
                NSApplication.shared.applicationIconImage = icon
            }

            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.6, dampingFraction: 0.9)) {
                appeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshUsage)) { _ in
            model.refresh()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image("BrandIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text("TOKIBURN")
                    .font(TokiburnTheme.body(14, weight: .bold))
                    .tracking(1.65)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tokiburn")

            HStack(spacing: 6) {
                Circle()
                    .fill(sourceIndicatorColor)
                    .frame(width: 5, height: 5)
                Text("\(sourceIndicatorLabel) · UPDATED \(model.report.loadedAt.formatted(date: .omitted, time: .shortened).uppercased())")
                    .font(TokiburnTheme.mono(9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(TokiburnTheme.secondary)
            }

            Spacer()

            PeriodSelector()
            RefreshButton()
        }
        .frame(height: 40)
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 50) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Eyebrow(text: model.selectedPeriod.title)
                    Text("·")
                        .foregroundStyle(TokiburnTheme.tertiary)
                    Text("Estimated list-price value")
                        .font(TokiburnTheme.body(11))
                        .foregroundStyle(TokiburnTheme.secondary)
                }

                Text(model.selectedCost.formCurrency)
                    .font(TokiburnTheme.display(68, weight: .semibold))
                    .tracking(-3.2)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: model.selectedCost))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Copy Value") {
                            copyToPasteboard(model.selectedCost.formCurrency)
                        }
                    }

                comparisonLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            Group {
                if model.selectedProviders.isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        Eyebrow(text: "Agent mix")
                        Text("No activity in this period")
                            .font(TokiburnTheme.body(12))
                            .foregroundStyle(TokiburnTheme.secondary)
                    }
                } else {
                    ProviderMix(
                        providers: model.selectedProviders,
                        totalCost: model.selectedCost,
                        totalTokens: model.selectedTokens
                    )
                }
            }
            .frame(width: 330)
            .padding(.bottom, 3)
        }
        .padding(.top, 36)
        .padding(.bottom, 30)
    }

    @ViewBuilder
    private var comparisonLine: some View {
        HStack(spacing: 7) {
            if model.selectedPeriod == .all {
                Text(firstRecordedLabel)
            } else if let comparison = model.selectedComparison {
                if let change = comparison.changeFraction {
                    Image(systemName: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(abs(change), format: .percent.precision(.fractionLength(0)))
                        .fontWeight(.semibold)
                    Text(comparison.previousLabel)
                        .foregroundStyle(TokiburnTheme.tertiary)
                } else {
                    Text("No recorded activity in the previous period")
                }
            } else {
                Text("No comparable earlier activity yet")
            }

            Button {
                showingEstimateInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("How this estimate works")
            .popover(isPresented: $showingEstimateInfo, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("About this estimate")
                        .font(TokiburnTheme.body(13, weight: .semibold))
                    Text("Tokiburn applies public API list prices to usage found in your local agent histories. It is a comparison estimate, not an amount billed.")
                        .font(TokiburnTheme.body(11))
                        .foregroundStyle(TokiburnTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: 280)
                .background(TokiburnTheme.surface)
            }
        }
        .font(TokiburnTheme.body(11))
        .foregroundStyle(TokiburnTheme.secondary)
        .accessibilityElement(children: .combine)
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(text: "Daily estimate")
                Spacer()
                Text(model.selectedDays.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "No data")
                    .font(TokiburnTheme.mono(9, weight: .medium))
                    .foregroundStyle(TokiburnTheme.tertiary)
            }

            Group {
                if model.selectedDays.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 16, weight: .medium))
                        Text("No activity recorded in this period")
                            .font(TokiburnTheme.body(11, weight: .medium))
                        Text("Choose another range or refresh your local histories.")
                            .font(TokiburnTheme.body(10))
                            .foregroundStyle(TokiburnTheme.tertiary)
                    }
                    .foregroundStyle(TokiburnTheme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TokiburnTheme.lineSoft.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    UsageTrendChart(days: model.selectedDays)
                }
            }
            .frame(height: 190)
        }
        .padding(.top, 18)
        .padding(.bottom, 22)
        .overlay(alignment: .top) { hairline }
    }

    private var activity: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Activity")
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(recentActiveDays)")
                        .font(TokiburnTheme.display(28, weight: .semibold))
                        .monospacedDigit()
                    Text("active days")
                        .font(TokiburnTheme.body(11))
                        .foregroundStyle(TokiburnTheme.secondary)
                }
                Text("Past 18 weeks")
                    .font(TokiburnTheme.mono(9, weight: .medium))
                    .foregroundStyle(TokiburnTheme.tertiary)
            }
            .frame(width: 160, alignment: .leading)

            Rectangle()
                .fill(TokiburnTheme.line)
                .frame(width: 1, height: 78)

            ActivityHeatmap()
                .frame(width: 420, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack {
            Image(systemName: footerIcon)
                .font(.system(size: 9, weight: .semibold))
            Text(footerStatus)
            Spacer()
            if model.report.archiveURL != nil {
                Button("Show local archive") {
                    NSWorkspace.shared.activateFileViewerSelecting([UsageArchive.defaultURL])
                }
                .buttonStyle(.plain)
                .foregroundStyle(TokiburnTheme.secondary)
            }
        }
        .font(TokiburnTheme.body(9))
        .foregroundStyle(TokiburnTheme.tertiary)
        .padding(.top, 4)
    }

    private var footerStatus: String {
        if model.report.isDemo {
            return "ccusage is unavailable, so Tokiburn is showing sample data."
        }
        if model.report.isArchiveOnly {
            return "Live histories are unavailable; these totals come from your local archive."
        }
        if model.report.archiveURL != nil {
            return "Daily totals are read locally and preserved in a private archive on this Mac."
        }
        return "Live local histories loaded; the private archive could not be updated."
    }

    private var footerIcon: String {
        model.report.isDemo || model.report.isArchiveOnly || model.report.archiveURL == nil
            ? "exclamationmark.triangle"
            : "lock"
    }

    private var sourceIndicatorLabel: String {
        if model.report.isDemo { return "PREVIEW" }
        if model.report.isArchiveOnly { return "ARCHIVE" }
        return "LOCAL"
    }

    private var sourceIndicatorColor: Color {
        if model.report.isDemo { return TokiburnTheme.warning }
        if model.report.isArchiveOnly { return TokiburnTheme.accent }
        return TokiburnTheme.positive
    }

    private var firstRecordedLabel: String {
        guard let first = model.report.days.map(\.date).min() else {
            return "No recorded activity yet"
        }
        return "Recorded since \(first.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var recentActiveDays: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -125, to: today) ?? today
        return Set(
            model.report.days
                .map { calendar.startOfDay(for: $0.date) }
                .filter { $0 >= start && $0 <= today }
        ).count
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var hairline: some View {
        Rectangle()
            .fill(TokiburnTheme.line)
            .frame(height: 1)
    }
}

private struct UsageTrendChart: View {
    let days: [DailyUsage]
    @State private var selectedDate: Date?

    private var selectedDay: DailyUsage? {
        guard let selectedDate else { return nil }
        return days.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var yDomain: ClosedRange<Double> {
        let maximum = days.map(\.totalCost).max() ?? 0
        return 0...max(maximum * 1.12, 1)
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                AreaMark(
                    x: .value("Date", day.date),
                    y: .value("Estimate", day.totalCost)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [TokiburnTheme.accent.opacity(0.16), TokiburnTheme.accent.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", day.date),
                    y: .value("Estimate", day.totalCost)
                )
                .foregroundStyle(TokiburnTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            if let selectedDay {
                RuleMark(x: .value("Selected", selectedDay.date))
                    .foregroundStyle(TokiburnTheme.ink.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("Selected", selectedDay.date),
                    y: .value("Estimate", selectedDay.totalCost)
                )
                .foregroundStyle(TokiburnTheme.accent)
                .symbolSize(36)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(Color.clear)
                AxisTick().foregroundStyle(TokiburnTheme.line)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(TokiburnTheme.mono(8))
                    .foregroundStyle(TokiburnTheme.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(TokiburnTheme.lineSoft)
                AxisTick().foregroundStyle(Color.clear)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formWholeCurrency)
                            .font(TokiburnTheme.mono(8))
                            .foregroundStyle(TokiburnTheme.tertiary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = proxy.plotFrame.map { geometry[$0] }

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard let plotFrame else { return }
                        switch phase {
                        case .active(let location):
                            selectedDate = proxy.value(atX: location.x - plotFrame.minX)
                        case .ended:
                            selectedDate = nil
                        }
                    }

                if
                    let selectedDay,
                    let plotFrame,
                    let x = proxy.position(forX: selectedDay.date),
                    let y = proxy.position(forY: selectedDay.totalCost)
                {
                    let tooltipWidth: CGFloat = 106
                    let tooltipHeight: CGFloat = 42
                    let pointX = plotFrame.minX + x
                    let pointY = plotFrame.minY + y
                    let tooltipX = min(
                        max(pointX, plotFrame.minX + tooltipWidth / 2),
                        plotFrame.maxX - tooltipWidth / 2
                    )
                    let preferredY = y > tooltipHeight + 12
                        ? pointY - tooltipHeight / 2 - 9
                        : pointY + tooltipHeight / 2 + 9
                    let tooltipY = min(
                        max(preferredY, plotFrame.minY + tooltipHeight / 2),
                        plotFrame.maxY - tooltipHeight / 2
                    )

                    ChartTooltip(day: selectedDay)
                        .frame(width: tooltipWidth, height: tooltipHeight)
                        .position(x: tooltipX, y: tooltipY)
                        .allowsHitTesting(false)
                }
            }
        }
        .contextMenu {
            if let selectedDay {
                Button("Copy \(selectedDay.totalCost.formCurrency)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(selectedDay.totalCost.formCurrency, forType: .string)
                }
            } else {
                Text("Hover a day to copy its value")
            }
        }
        .accessibilityLabel("Daily API-equivalent cost estimate")
    }
}

private struct ChartTooltip: View {
    let day: DailyUsage

    var body: some View {
        VStack(spacing: 2) {
            Text(day.totalCost.formCurrency)
                .font(TokiburnTheme.mono(10, weight: .bold))
                .foregroundStyle(TokiburnTheme.ink)
            Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(TokiburnTheme.body(9))
                .foregroundStyle(TokiburnTheme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TokiburnTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokiburnTheme.line, lineWidth: 1)
        }
        .shadow(color: TokiburnTheme.ink.opacity(0.06), radius: 8, y: 3)
        .accessibilityHidden(true)
    }
}
