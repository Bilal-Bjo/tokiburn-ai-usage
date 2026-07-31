import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var report = UsageLoader.demo()
    @Published var selectedPeriod: UsagePeriod = .month
    @Published var isRefreshing = false

    var selectedCost: Double {
        report.cost(in: selectedPeriod)
    }

    var selectedDays: [DailyUsage] {
        report.days(in: selectedPeriod)
    }

    var selectedTokens: Int {
        report.tokens(in: selectedPeriod)
    }

    var selectedProviders: [ProviderUsage] {
        report.providerTotals(in: selectedPeriod)
    }

    var selectedActiveDays: Int {
        report.activeDays(in: selectedPeriod)
    }

    var selectedComparison: PeriodComparison? {
        report.comparison(for: selectedPeriod)
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--provider-preview") {
            report = Self.providerPreviewReport()
            return
        }
        #endif
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let loaded = await UsageLoader.load()
            report = loaded
            isRefreshing = false
        }
    }

    func select(_ period: UsagePeriod) {
        selectedPeriod = period
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
