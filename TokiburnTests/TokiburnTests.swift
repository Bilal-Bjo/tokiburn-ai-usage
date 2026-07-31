import XCTest
@testable import Tokiburn

final class TokiburnTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testPeriodTotalsAreCalendarCorrect() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31))!
        let report = UsageReport(
            days: [
                day(2025, 7, 31, cost: 1),
                day(2026, 1, 2, cost: 10),
                day(2026, 6, 30, cost: 20),
                day(2026, 7, 1, cost: 30),
                day(2026, 7, 31, cost: 40)
            ],
            isDemo: false,
            loadedAt: now,
            sourceVersion: "20.0.19"
        )

        XCTAssertEqual(report.cost(in: .month, now: now, calendar: calendar), 70, accuracy: 0.001)
        XCTAssertEqual(report.cost(in: .yearToDate, now: now, calendar: calendar), 100, accuracy: 0.001)
        XCTAssertEqual(report.cost(in: .rollingYear, now: now, calendar: calendar), 100, accuracy: 0.001)
        XCTAssertEqual(report.cost(in: .all, now: now, calendar: calendar), 101, accuracy: 0.001)
    }

    func testCCUsageUnifiedJSONDecodesAgentBreakdowns() throws {
        let json = """
        {
          "daily": [{
            "agent": "all",
            "period": "2026-07-30",
            "inputTokens": 15,
            "outputTokens": 5,
            "cacheReadTokens": 80,
            "totalTokens": 100,
            "totalCost": 2.5,
            "agents": [
              {
                "agent": "codex",
                "inputTokens": 10,
                "outputTokens": 2,
                "cacheReadTokens": 58,
                "totalTokens": 70,
                "totalCost": 2.0
              },
              {
                "agent": "claude",
                "inputTokens": 5,
                "outputTokens": 3,
                "cacheReadTokens": 22,
                "totalTokens": 30,
                "totalCost": 0.5
              }
            ]
          }],
          "monthly": [],
          "totals": {}
        }
        """

        let report = try UsageLoader.decode(Data(json.utf8))
        XCTAssertEqual(report.days.count, 1)
        XCTAssertEqual(report.days[0].providers.count, 2)
        XCTAssertEqual(report.days[0].totalTokens, 100)
        XCTAssertEqual(report.days[0].totalCost, 2.5, accuracy: 0.001)
    }

    func testMonthComparisonUsesSameCutoffInPreviousMonth() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        let report = UsageReport(
            days: [
                day(2026, 6, 1, cost: 10),
                day(2026, 6, 15, cost: 20),
                day(2026, 6, 16, cost: 1_000),
                day(2026, 7, 1, cost: 45)
            ],
            isDemo: false,
            loadedAt: now,
            sourceVersion: nil
        )

        let comparison = report.comparison(for: .month, now: now, calendar: calendar)

        XCTAssertEqual(comparison?.currentCost ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(comparison?.previousCost ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(comparison?.changeFraction ?? 0, 0.5, accuracy: 0.001)
    }

    func testMonthComparisonClampsToShorterPreviousMonth() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let report = UsageReport(
            days: [
                day(2026, 2, 28, cost: 12),
                day(2026, 3, 31, cost: 18)
            ],
            isDemo: false,
            loadedAt: now,
            sourceVersion: nil
        )

        let comparison = report.comparison(for: .month, now: now, calendar: calendar)

        XCTAssertEqual(comparison?.previousCost ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(comparison?.currentCost ?? 0, 18, accuracy: 0.001)
    }

    func testYTDComparisonUsesCalendarDateAcrossLeapYear() {
        let now = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!
        let report = UsageReport(
            days: [
                day(2023, 3, 1, cost: 20),
                day(2023, 3, 2, cost: 1_000),
                day(2024, 3, 1, cost: 30)
            ],
            isDemo: false,
            loadedAt: now,
            sourceVersion: nil
        )

        let comparison = report.comparison(for: .yearToDate, now: now, calendar: calendar)

        XCTAssertEqual(comparison?.previousCost ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(comparison?.currentCost ?? 0, 30, accuracy: 0.001)
    }

    func testAllTimeDoesNotInventAPriorComparison() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31))!
        let report = UsageReport(
            days: [day(2026, 7, 31, cost: 10)],
            isDemo: false,
            loadedAt: now,
            sourceVersion: nil
        )

        XCTAssertNil(report.comparison(for: .all, now: now, calendar: calendar))
    }

    func testProviderTotalsSortByCost() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30))!
        let report = UsageReport(
            days: [
                DailyUsage(
                    date: date,
                    providers: [
                        ProviderUsage(agent: "claude", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, totalTokens: 20, cost: 1),
                        ProviderUsage(agent: "codex", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, totalTokens: 10, cost: 2)
                    ]
                )
            ],
            isDemo: false,
            loadedAt: date,
            sourceVersion: nil
        )

        XCTAssertEqual(report.providerTotals.map(\.agent), ["codex", "claude"])
    }

    func testProviderRowsCompactTenSourcesWithoutLosingTotals() {
        let providers = (1...10).reversed().map { index in
            ProviderUsage(
                agent: "agent-\(index)",
                inputTokens: index,
                outputTokens: index,
                cacheReadTokens: index,
                totalTokens: index * 3,
                cost: Double(index)
            )
        }

        let rows = providers.compacted(maximumRows: 4)

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.prefix(3).map(\.agent), ["agent-10", "agent-9", "agent-8"])
        XCTAssertEqual(rows.last?.agent, "Other 7")
        XCTAssertEqual(rows.reduce(0) { $0 + $1.totalTokens }, providers.reduce(0) { $0 + $1.totalTokens })
        XCTAssertEqual(rows.reduce(0) { $0 + $1.cost }, providers.reduce(0) { $0 + $1.cost }, accuracy: 0.001)
    }

    func testArchivePreservesMissingHistoryAndUpdatesLiveRows() throws {
        let url = try temporaryArchiveURL()
        let firstSnapshot = [
            day(2026, 6, 30, cost: 10),
            day(2026, 7, 1, cost: 20)
        ]
        _ = try UsageArchive.merge(liveDays: firstSnapshot, at: url)

        let secondSnapshot = [
            day(2026, 7, 1, cost: 25),
            day(2026, 7, 2, cost: 30)
        ]
        let merged = try UsageArchive.merge(liveDays: secondSnapshot, at: url)

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0].totalCost, 10, accuracy: 0.001)
        XCTAssertEqual(merged[1].totalCost, 25, accuracy: 0.001)
        XCTAssertEqual(merged[2].totalCost, 30, accuracy: 0.001)

        let reloaded = try UsageArchive.load(from: url)
        XCTAssertEqual(reloaded, merged)

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? 0, 0o600)
    }

    func testArchiveRoundTripsQuotedAgentNames() throws {
        let url = try temporaryArchiveURL()
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30))!
        let source = DailyUsage(
            date: date,
            providers: [
                ProviderUsage(
                    agent: "agent, \"beta\"",
                    inputTokens: 1,
                    outputTokens: 2,
                    cacheReadTokens: 3,
                    totalTokens: 6,
                    cost: 1.23456789
                )
            ]
        )

        try UsageArchive.save([source], to: url)
        let loaded = try UsageArchive.load(from: url)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].providers[0].agent, "agent, \"beta\"")
        XCTAssertEqual(loaded[0].providers[0].cost, 1.23456789, accuracy: 0.000000001)
    }

    func testLegacyArchiveMigrationPreservesHistoryWithoutOverwritingDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokiburn-migration-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = directory.appendingPathComponent("FORM/usage-history.csv")
        let destinationURL = directory.appendingPathComponent("Tokiburn/usage-history.csv")
        try UsageArchive.save([day(2026, 7, 29, cost: 12)], to: legacyURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        try UsageArchive.migrateLegacyArchive(from: legacyURL, to: destinationURL)

        XCTAssertEqual(try UsageArchive.load(from: destinationURL).first?.totalCost, 12)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: destinationURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? 0, 0o600)

        try UsageArchive.save([day(2026, 7, 30, cost: 24)], to: legacyURL)
        try UsageArchive.migrateLegacyArchive(from: legacyURL, to: destinationURL)
        XCTAssertEqual(try UsageArchive.load(from: destinationURL).first?.totalCost, 12)
    }

    private func day(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        cost: Double
    ) -> DailyUsage {
        let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
        return DailyUsage(
            date: date,
            providers: [
                ProviderUsage(
                    agent: "codex",
                    inputTokens: 1,
                    outputTokens: 1,
                    cacheReadTokens: 0,
                    totalTokens: 2,
                    cost: cost
                )
            ]
        )
    }

    private func temporaryArchiveURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("form-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("usage-history.csv")
    }
}
