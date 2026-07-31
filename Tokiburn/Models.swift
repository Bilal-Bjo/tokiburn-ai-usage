import Foundation

struct ProviderUsage: Identifiable, Hashable {
    let agent: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let cost: Double

    var id: String { agent }
}

extension Array where Element == ProviderUsage {
    func compacted(maximumRows: Int) -> [ProviderUsage] {
        guard maximumRows > 0 else { return [] }
        guard count > maximumRows else { return self }

        let visibleCount = maximumRows - 1
        let remainder = dropFirst(visibleCount)
        let other = ProviderUsage(
            agent: "Other \(remainder.count)",
            inputTokens: remainder.reduce(0) { $0 + $1.inputTokens },
            outputTokens: remainder.reduce(0) { $0 + $1.outputTokens },
            cacheReadTokens: remainder.reduce(0) { $0 + $1.cacheReadTokens },
            totalTokens: remainder.reduce(0) { $0 + $1.totalTokens },
            cost: remainder.reduce(0) { $0 + $1.cost }
        )

        return Array(prefix(visibleCount)) + [other]
    }
}

struct DailyUsage: Identifiable, Hashable {
    let date: Date
    let providers: [ProviderUsage]

    var id: Date { date }
    var totalTokens: Int { providers.reduce(0) { $0 + $1.totalTokens } }
    var totalCost: Double { providers.reduce(0) { $0 + $1.cost } }
}

struct PeriodComparison: Equatable {
    let currentCost: Double
    let previousCost: Double
    let previousLabel: String

    var changeFraction: Double? {
        guard previousCost > 0 else { return nil }
        return (currentCost - previousCost) / previousCost
    }
}

struct UsageReport {
    let days: [DailyUsage]
    let isDemo: Bool
    let loadedAt: Date
    let sourceVersion: String?
    let archiveURL: URL?
    let isArchiveOnly: Bool

    init(
        days: [DailyUsage],
        isDemo: Bool,
        loadedAt: Date,
        sourceVersion: String?,
        archiveURL: URL? = nil,
        isArchiveOnly: Bool = false
    ) {
        self.days = days
        self.isDemo = isDemo
        self.loadedAt = loadedAt
        self.sourceVersion = sourceVersion
        self.archiveURL = archiveURL
        self.isArchiveOnly = isArchiveOnly
    }

    var providerTotals: [ProviderUsage] {
        let grouped = Dictionary(grouping: days.flatMap(\.providers), by: \.agent)
        return grouped.map { agent, values in
            ProviderUsage(
                agent: agent,
                inputTokens: values.reduce(0) { $0 + $1.inputTokens },
                outputTokens: values.reduce(0) { $0 + $1.outputTokens },
                cacheReadTokens: values.reduce(0) { $0 + $1.cacheReadTokens },
                totalTokens: values.reduce(0) { $0 + $1.totalTokens },
                cost: values.reduce(0) { $0 + $1.cost }
            )
        }
        .sorted { lhs, rhs in
            if lhs.cost == rhs.cost { return lhs.totalTokens > rhs.totalTokens }
            return lhs.cost > rhs.cost
        }
    }

    var activeDays: Int {
        Set(days.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var allTimeCost: Double {
        days.reduce(0) { $0 + $1.totalCost }
    }

    func providerTotals(in period: UsagePeriod, now: Date = Date(), calendar: Calendar = .current) -> [ProviderUsage] {
        let grouped = Dictionary(
            grouping: days(in: period, now: now, calendar: calendar).flatMap(\.providers),
            by: \.agent
        )
        return grouped.map { agent, values in
            ProviderUsage(
                agent: agent,
                inputTokens: values.reduce(0) { $0 + $1.inputTokens },
                outputTokens: values.reduce(0) { $0 + $1.outputTokens },
                cacheReadTokens: values.reduce(0) { $0 + $1.cacheReadTokens },
                totalTokens: values.reduce(0) { $0 + $1.totalTokens },
                cost: values.reduce(0) { $0 + $1.cost }
            )
        }
        .sorted { lhs, rhs in
            if lhs.cost == rhs.cost { return lhs.totalTokens > rhs.totalTokens }
            return lhs.cost > rhs.cost
        }
    }

    func cost(in period: UsagePeriod, now: Date = Date(), calendar: Calendar = .current) -> Double {
        days
            .filter { period.contains($0.date, now: now, calendar: calendar) }
            .reduce(0) { $0 + $1.totalCost }
    }

    func tokens(in period: UsagePeriod, now: Date = Date(), calendar: Calendar = .current) -> Int {
        days
            .filter { period.contains($0.date, now: now, calendar: calendar) }
            .reduce(0) { $0 + $1.totalTokens }
    }

    func days(in period: UsagePeriod, now: Date = Date(), calendar: Calendar = .current) -> [DailyUsage] {
        days.filter { period.contains($0.date, now: now, calendar: calendar) }
    }

    func activeDays(in period: UsagePeriod, now: Date = Date(), calendar: Calendar = .current) -> Int {
        Set(days(in: period, now: now, calendar: calendar).map { calendar.startOfDay(for: $0.date) }).count
    }

    func comparison(
        for period: UsagePeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PeriodComparison? {
        guard let previousInterval = period.previousInterval(now: now, calendar: calendar) else {
            return nil
        }

        let previousDays = days.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= previousInterval.start && day < previousInterval.end
        }
        guard !previousDays.isEmpty else { return nil }

        return PeriodComparison(
            currentCost: cost(in: period, now: now, calendar: calendar),
            previousCost: previousDays.reduce(0) { $0 + $1.totalCost },
            previousLabel: period.previousComparisonLabel
        )
    }
}

enum UsagePeriod: String, CaseIterable, Identifiable {
    case month
    case yearToDate
    case rollingYear
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "This month"
        case .yearToDate: "Year to date"
        case .rollingYear: "Last 12 months"
        case .all: "All time"
        }
    }

    var shortTitle: String {
        switch self {
        case .month: "Month"
        case .yearToDate: "YTD"
        case .rollingYear: "1 Year"
        case .all: "All"
        }
    }

    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard day <= today else { return false }

        switch self {
        case .month:
            return calendar.isDate(day, equalTo: today, toGranularity: .month)
        case .yearToDate:
            return calendar.component(.year, from: day) == calendar.component(.year, from: today)
        case .rollingYear:
            let start = calendar.date(byAdding: .day, value: -364, to: today) ?? today
            return day >= start
        case .all:
            return true
        }
    }

    var previousComparisonLabel: String {
        switch self {
        case .month: "vs previous month to date"
        case .yearToDate: "vs same point last year"
        case .rollingYear: "vs preceding 12 months"
        case .all: ""
        }
    }

    func previousInterval(now: Date, calendar: Calendar) -> DateInterval? {
        let today = calendar.startOfDay(for: now)

        switch self {
        case .month:
            guard
                let currentMonth = calendar.dateInterval(of: .month, for: today),
                let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonth.start),
                let previousMonth = calendar.dateInterval(of: .month, for: previousMonthStart)
            else { return nil }

            let dayOffset = calendar.dateComponents([.day], from: currentMonth.start, to: today).day ?? 0
            let desiredEnd = calendar.date(byAdding: .day, value: dayOffset + 1, to: previousMonth.start) ?? previousMonth.end
            return DateInterval(start: previousMonth.start, end: min(desiredEnd, previousMonth.end))

        case .yearToDate:
            guard
                let previousCutoff = calendar.date(byAdding: .year, value: -1, to: today),
                let previousYear = calendar.dateInterval(of: .year, for: previousCutoff),
                let desiredEnd = calendar.date(byAdding: .day, value: 1, to: previousCutoff)
            else { return nil }
            return DateInterval(start: previousYear.start, end: min(desiredEnd, previousYear.end))

        case .rollingYear:
            guard
                let currentStart = calendar.date(byAdding: .day, value: -364, to: today),
                let previousStart = calendar.date(byAdding: .day, value: -365, to: currentStart)
            else { return nil }
            return DateInterval(start: previousStart, end: currentStart)

        case .all:
            return nil
        }
    }
}
