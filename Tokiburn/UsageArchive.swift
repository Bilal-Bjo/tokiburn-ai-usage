import Foundation

enum UsageArchiveError: Error {
    case malformedHeader
    case malformedRow(Int)
    case invalidDate(Int)
    case invalidNumber(Int)
}

enum UsageArchive {
    static var defaultURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("Tokiburn", isDirectory: true)
            .appendingPathComponent("usage-history.csv", isDirectory: false)
    }

    static var legacyURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("FORM", isDirectory: true)
            .appendingPathComponent("usage-history.csv", isDirectory: false)
    }

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    static func merge(liveDays: [DailyUsage], at url: URL = defaultURL) throws -> [DailyUsage] {
        let archivedDays = try load(from: url)
        var rows: [ArchiveKey: ArchiveRow] = [:]

        for row in flatten(archivedDays) {
            rows[row.key] = row
        }
        for row in flatten(liveDays) {
            rows[row.key] = row
        }

        let merged = inflate(Array(rows.values))
        try save(merged, to: url)
        return merged
    }

    static func load(from url: URL = defaultURL) throws -> [DailyUsage] {
        if url.standardizedFileURL == defaultURL.standardizedFileURL {
            try migrateLegacyArchive(from: legacyURL, to: url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first else { return [] }
        guard parseCSVLine(header) == ArchiveRow.header else {
            throw UsageArchiveError.malformedHeader
        }

        let rows = try lines.dropFirst().enumerated().map { offset, line in
            try ArchiveRow(fields: parseCSVLine(line), line: offset + 2)
        }
        return inflate(rows)
    }

    static func migrateLegacyArchive(from legacyURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard
            !fileManager.fileExists(atPath: destinationURL.path),
            fileManager.fileExists(atPath: legacyURL.path)
        else {
            return
        }

        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.copyItem(at: legacyURL, to: destinationURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destinationURL.path
        )
    }

    static func save(_ days: [DailyUsage], to url: URL = defaultURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let rows = flatten(days).sorted {
            if $0.day == $1.day { return $0.agent < $1.agent }
            return $0.day < $1.day
        }
        let lines = [
            ArchiveRow.header.map(escapeCSVField).joined(separator: ",")
        ] + rows.map(\.csv)
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func flatten(_ days: [DailyUsage]) -> [ArchiveRow] {
        days.flatMap { day in
            day.providers.map { provider in
                ArchiveRow(
                    day: dayFormatter.string(from: day.date),
                    agent: provider.agent,
                    inputTokens: provider.inputTokens,
                    outputTokens: provider.outputTokens,
                    cacheReadTokens: provider.cacheReadTokens,
                    totalTokens: provider.totalTokens,
                    estimatedCostUSD: provider.cost
                )
            }
        }
    }

    private static func inflate(_ rows: [ArchiveRow]) -> [DailyUsage] {
        let grouped = Dictionary(grouping: rows, by: \.day)
        return grouped.compactMap { day, rows -> DailyUsage? in
            guard let date = dayFormatter.date(from: day) else { return nil }
            let providers = rows
                .map {
                    ProviderUsage(
                        agent: $0.agent,
                        inputTokens: $0.inputTokens,
                        outputTokens: $0.outputTokens,
                        cacheReadTokens: $0.cacheReadTokens,
                        totalTokens: $0.totalTokens,
                        cost: $0.estimatedCostUSD
                    )
                }
                .sorted { $0.agent < $1.agent }
            return DailyUsage(date: date, providers: providers)
        }
        .sorted { $0.date < $1.date }
    }

    private static func escapeCSVField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        let characters = Array(line)
        var fields: [String] = []
        var field = ""
        var quoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                }
                quoted.toggle()
            } else if character == ",", !quoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        fields.append(field)
        return fields
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ArchiveKey: Hashable {
    let day: String
    let agent: String
}

private struct ArchiveRow {
    static let header = [
        "date",
        "agent",
        "input_tokens",
        "output_tokens",
        "cache_read_tokens",
        "total_tokens",
        "estimated_cost_usd"
    ]

    let day: String
    let agent: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double

    var key: ArchiveKey {
        ArchiveKey(day: day, agent: agent)
    }

    var csv: String {
        [
            day,
            agent,
            String(inputTokens),
            String(outputTokens),
            String(cacheReadTokens),
            String(totalTokens),
            String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), estimatedCostUSD)
        ]
        .map { value in
            guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
                return value
            }
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        .joined(separator: ",")
    }

    init(
        day: String,
        agent: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        totalTokens: Int,
        estimatedCostUSD: Double
    ) {
        self.day = day
        self.agent = agent
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    init(fields: [String], line: Int) throws {
        guard fields.count == Self.header.count else {
            throw UsageArchiveError.malformedRow(line)
        }
        guard UsageArchiveDateValidator.isValid(fields[0]) else {
            throw UsageArchiveError.invalidDate(line)
        }
        guard
            let inputTokens = Int(fields[2]),
            let outputTokens = Int(fields[3]),
            let cacheReadTokens = Int(fields[4]),
            let totalTokens = Int(fields[5]),
            let estimatedCostUSD = Double(fields[6])
        else {
            throw UsageArchiveError.invalidNumber(line)
        }

        self.init(
            day: fields[0],
            agent: fields[1],
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            totalTokens: totalTokens,
            estimatedCostUSD: estimatedCostUSD
        )
    }
}

private enum UsageArchiveDateValidator {
    static func isValid(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let parts = value.split(separator: "-")
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) != nil
    }
}
