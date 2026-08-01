import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var report = UsageLoader.demo()
    @Published var selectedPeriod: UsagePeriod = .month
    @Published private(set) var selectedMonthStart: Date
    @Published var isRefreshing = false

    private let calendar: Calendar
    private let now: () -> Date

    var selectedCost: Double {
        report.cost(in: selectedPeriod, now: selectedReferenceDate, calendar: calendar)
    }

    var selectedDays: [DailyUsage] {
        report.days(in: selectedPeriod, now: selectedReferenceDate, calendar: calendar)
    }

    var selectedTokens: Int {
        report.tokens(in: selectedPeriod, now: selectedReferenceDate, calendar: calendar)
    }

    var selectedProviders: [ProviderUsage] {
        report.providerTotals(in: selectedPeriod, now: selectedReferenceDate, calendar: calendar)
    }

    var selectedActiveDays: Int {
        report.activeDays(in: selectedPeriod, now: selectedReferenceDate, calendar: calendar)
    }

    var selectedComparison: PeriodComparison? {
        guard let comparison = report.comparison(
            for: selectedPeriod,
            now: selectedReferenceDate,
            calendar: calendar
        ) else {
            return nil
        }

        guard selectedPeriod == .month, !isCurrentMonth else {
            return comparison
        }

        return PeriodComparison(
            currentCost: comparison.currentCost,
            previousCost: comparison.previousCost,
            previousLabel: "vs previous month"
        )
    }

    var selectedPeriodTitle: String {
        selectedPeriod == .month ? selectedMonthTitle : selectedPeriod.title
    }

    var selectedMonthTitle: String {
        selectedMonthStart.formatted(.dateTime.month(.wide).year())
    }

    var canSelectPreviousMonth: Bool {
        guard let earliestMonthStart else { return false }
        return selectedMonthStart > earliestMonthStart
    }

    var canSelectNextMonth: Bool {
        selectedMonthStart < currentMonthStart
    }

    var activityAnchorDate: Date {
        selectedPeriod == .month ? selectedReferenceDate : now()
    }

    var activityRangeLabel: String {
        if selectedPeriod == .month, !isCurrentMonth {
            return "18 weeks ending \(selectedMonthStart.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return "Past 18 weeks"
    }

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        autoRefresh: Bool = true
    ) {
        self.calendar = calendar
        self.now = now
        self.selectedMonthStart = calendar.dateInterval(of: .month, for: now())?.start ?? now()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--provider-preview") {
            report = Self.providerPreviewReport()
            return
        }
        #endif
        if autoRefresh {
            refresh()
        }
    }

    func refresh() {
        Task {
            _ = await refreshNow()
        }
    }

    @discardableResult
    func refreshNow() async -> UsageReport? {
        guard !isRefreshing else { return nil }
        isRefreshing = true
        defer { isRefreshing = false }

        let loaded = await UsageLoader.load()
        report = loaded
        return loaded
    }

    func select(_ period: UsagePeriod) {
        selectedPeriod = period
    }

    func selectAdjacentMonth(_ offset: Int) {
        guard offset == -1 || offset == 1 else { return }
        guard let candidate = calendar.date(byAdding: .month, value: offset, to: selectedMonthStart) else {
            return
        }

        if offset < 0, canSelectPreviousMonth {
            selectedMonthStart = max(candidate, earliestMonthStart ?? candidate)
        } else if offset > 0, canSelectNextMonth {
            selectedMonthStart = min(candidate, currentMonthStart)
        }
    }

    private var currentMonthStart: Date {
        calendar.dateInterval(of: .month, for: now())?.start ?? calendar.startOfDay(for: now())
    }

    private var earliestMonthStart: Date? {
        guard let earliest = report.days.map(\.date).min() else { return nil }
        return calendar.dateInterval(of: .month, for: earliest)?.start
    }

    private var isCurrentMonth: Bool {
        selectedMonthStart == currentMonthStart
    }

    private var selectedReferenceDate: Date {
        guard selectedPeriod == .month, !isCurrentMonth else { return now() }
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonthStart) else {
            return selectedMonthStart
        }
        return nextMonth.addingTimeInterval(-1)
    }

    #if DEBUG
    private static func providerPreviewReport() -> UsageReport {
        let names = [
            "codex", "claude", "gemini", "copilot", "kimi",
            "opencode", "qwen", "amp", "goose", "openclaw"
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<24).compactMap { offset -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let providers = names.enumerated().map { index, name in
                let weight = Double(names.count - index)
                let dailyVariation = Double((offset % 4) + 1) * 0.17
                return ProviderUsage(
                    agent: name,
                    inputTokens: (index + 1) * 12_000,
                    outputTokens: (index + 1) * 2_500,
                    cacheReadTokens: (index + 1) * 40_000,
                    totalTokens: (index + 1) * 54_500,
                    cost: weight * dailyVariation
                )
            }
            return DailyUsage(date: date, providers: providers)
        }

        return UsageReport(
            days: days.sorted { $0.date < $1.date },
            isDemo: true,
            loadedAt: Date(),
            sourceVersion: nil
        )
    }
    #endif
}
