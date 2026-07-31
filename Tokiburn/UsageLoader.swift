import Foundation

enum UsageLoaderError: LocalizedError {
    case executableUnavailable
    case commandFailed(String)
    case commandTimedOut
    case emptyReport

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            "ccusage is not installed at a supported local path."
        case .commandFailed(let message):
            "ccusage failed: \(message)"
        case .commandTimedOut:
            "ccusage took too long to respond."
        case .emptyReport:
            "No local agent history was found."
        }
    }
}

enum UsageLoader {
    static func load() async -> UsageReport {
        do {
            return try await loadLive()
        } catch {
            do {
                let archivedDays = try await Task.detached(priority: .userInitiated) {
                    try UsageArchive.load()
                }.value
                guard !archivedDays.isEmpty else { return demo() }
                return UsageReport(
                    days: archivedDays,
                    isDemo: false,
                    loadedAt: Date(),
                    sourceVersion: nil,
                    archiveURL: UsageArchive.defaultURL,
                    isArchiveOnly: true
                )
            } catch {
                return demo()
            }
        }
    }

    static func loadLive() async throws -> UsageReport {
        try await Task.detached(priority: .userInitiated) {
            guard let executable = ccusageExecutable() else {
                throw UsageLoaderError.executableUnavailable
            }

            let data = try run(
                executable: executable,
                arguments: [
                    "daily",
                    "--sections", "daily,monthly",
                    "--by-agent",
                    "--json",
                    "--offline",
                    "--timezone", TimeZone.current.identifier
                ],
                timeout: 25
            )
            let decoded = try JSONDecoder().decode(CCUsageEnvelope.self, from: data)
            let formatter = ISO8601DateFormatter.formDay

            let days = decoded.daily.compactMap { row -> DailyUsage? in
                guard let date = formatter.date(from: row.period) else { return nil }
                let providers = (row.agents ?? []).map { agent in
                    ProviderUsage(
                        agent: displayAgent(agent.agent),
                        inputTokens: agent.inputTokens,
                        outputTokens: agent.outputTokens,
                        cacheReadTokens: agent.cacheReadTokens,
                        totalTokens: agent.totalTokens,
                        cost: agent.totalCost
                    )
                }
                let resolvedProviders = providers.isEmpty
                    ? [
                        ProviderUsage(
                            agent: row.agent == "all" ? "local agents" : displayAgent(row.agent),
                            inputTokens: row.inputTokens,
                            outputTokens: row.outputTokens,
                            cacheReadTokens: row.cacheReadTokens,
                            totalTokens: row.totalTokens,
                            cost: row.totalCost
                        )
                    ]
                    : providers
                return DailyUsage(date: date, providers: resolvedProviders)
            }
            .sorted { $0.date < $1.date }

            guard !days.isEmpty else { throw UsageLoaderError.emptyReport }
            let version = try? readVersion(executable: executable)
            let archivedDays: [DailyUsage]
            let archiveURL: URL?
            do {
                archivedDays = try UsageArchive.merge(liveDays: days)
                archiveURL = UsageArchive.defaultURL
            } catch {
                archivedDays = days
                archiveURL = nil
            }
            return UsageReport(
                days: archivedDays,
                isDemo: false,
                loadedAt: Date(),
                sourceVersion: version,
                archiveURL: archiveURL
            )
        }.value
    }

    static func decode(_ data: Data, loadedAt: Date = Date()) throws -> UsageReport {
        let decoded = try JSONDecoder().decode(CCUsageEnvelope.self, from: data)
        let formatter = ISO8601DateFormatter.formDay
        let days = decoded.daily.compactMap { row -> DailyUsage? in
            guard let date = formatter.date(from: row.period) else { return nil }
            let providers = (row.agents ?? []).map {
                ProviderUsage(
                    agent: displayAgent($0.agent),
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    cacheReadTokens: $0.cacheReadTokens,
                    totalTokens: $0.totalTokens,
                    cost: $0.totalCost
                )
            }
            return DailyUsage(date: date, providers: providers)
        }
        guard !days.isEmpty else { throw UsageLoaderError.emptyReport }
        return UsageReport(days: days.sorted { $0.date < $1.date }, isDemo: false, loadedAt: loadedAt, sourceVersion: nil)
    }

    static func demo(now: Date = Date()) -> UsageReport {
        var generator = SeededGenerator(seed: 0xF0_4D)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var days: [DailyUsage] = []

        for offset in stride(from: 179, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            guard generator.nextUnit() > (weekday == 1 || weekday == 7 ? 0.58 : 0.22) else { continue }

            let codexTokens = Int(8_000_000 + generator.nextUnit() * 90_000_000)
            let claudeTokens = Int(3_000_000 + generator.nextUnit() * 45_000_000)
            var providers = [
                ProviderUsage(
                    agent: "codex",
                    inputTokens: codexTokens / 15,
                    outputTokens: codexTokens / 55,
                    cacheReadTokens: codexTokens * 8 / 10,
                    totalTokens: codexTokens,
                    cost: Double(codexTokens) / 1_000_000 * 0.84
                )
            ]
            if generator.nextUnit() > 0.30 {
                providers.append(
                    ProviderUsage(
                        agent: "claude",
                        inputTokens: claudeTokens / 75,
                        outputTokens: claudeTokens / 48,
                        cacheReadTokens: claudeTokens * 9 / 10,
                        totalTokens: claudeTokens,
                        cost: Double(claudeTokens) / 1_000_000 * 0.68
                    )
                )
            }
            days.append(DailyUsage(date: date, providers: providers))
        }

        return UsageReport(days: days, isDemo: true, loadedAt: now, sourceVersion: nil)
    }

    private static func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> Data {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("form-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let outputURL = temporary.appendingPathComponent("usage.json")
        let errorURL = temporary.appendingPathComponent("error.txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? errors.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["NO_COLOR": "1"],
            uniquingKeysWith: { _, new in new }
        )
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw UsageLoaderError.commandTimedOut
        }

        try output.synchronize()
        try errors.synchronize()
        guard process.terminationStatus == 0 else {
            let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "Unknown error"
            throw UsageLoaderError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Data(contentsOf: outputURL)
    }

    private static func readVersion(executable: String) throws -> String {
        let data = try run(executable: executable, arguments: ["--version"], timeout: 5)
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ccusage ", with: "")
            ?? "unknown"
    }

    private static func ccusageExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".bun/bin/ccusage").path,
            home.appendingPathComponent(".local/bin/ccusage").path,
            "/opt/homebrew/bin/ccusage",
            "/usr/local/bin/ccusage"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func displayAgent(_ value: String) -> String {
        switch value.lowercased() {
        case "claude_code": "claude"
        case "kimi_cli": "kimi"
        default: value.replacingOccurrences(of: "_", with: " ")
        }
    }
}

struct CCUsageEnvelope: Decodable {
    let daily: [CCUsageRow]
}

struct CCUsageRow: Decodable {
    let agent: String
    let period: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let agents: [CCUsageAgent]?
}

struct CCUsageAgent: Decodable {
    let agent: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
}

private extension ISO8601DateFormatter {
    static let formDay: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state = 2_862_933_555_777_941_757 &* state &+ 3_037_000_493
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }
}
