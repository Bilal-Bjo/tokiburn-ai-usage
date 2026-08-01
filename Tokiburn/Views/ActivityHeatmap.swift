import AppKit
import SwiftUI

struct ActivityHeatmap: View {
    @EnvironmentObject private var model: AppModel
    let anchorDate: Date

    private let columns = 18
    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Daily volume")
                Spacer()
                Text("Less")
                legendCell(opacity: 0.16)
                legendCell(opacity: 0.42)
                legendCell(opacity: 0.72)
                legendCell(opacity: 1)
                Text("More")
            }
            .font(TokiburnTheme.body(9))
            .foregroundStyle(TokiburnTheme.tertiary)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(week, id: \.self) { date in
                            dayCell(date)
                        }
                    }
                }
            }
        }
    }

    private var weeks: [[Date]] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: anchorDate)
        let weekday = calendar.component(.weekday, from: anchor)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: anchor) ?? anchor
        let start = calendar.date(byAdding: .day, value: -(columns - 1) * 7, to: monday) ?? anchor

        return (0..<columns).map { column in
            (0..<7).compactMap { row in
                calendar.date(byAdding: .day, value: column * 7 + row, to: start)
            }
        }
    }

    private var usageByDate: [Date: DailyUsage] {
        Dictionary(
            uniqueKeysWithValues: model.report.days.map {
                (Calendar.current.startOfDay(for: $0.date), $0)
            }
        )
    }

    private var maximumTokens: Int {
        max(model.report.days.map(\.totalTokens).max() ?? 1, 1)
    }

    private func dayCell(_ date: Date) -> some View {
        let normalized = Calendar.current.startOfDay(for: date)
        let usage = usageByDate[normalized]
        let intensity = usage.map {
            log10(Double($0.totalTokens) + 1) / log10(Double(maximumTokens) + 1)
        } ?? 0
        let future = normalized > Calendar.current.startOfDay(for: anchorDate)

        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(
                future
                    ? Color.clear
                    : intensity == 0
                        ? TokiburnTheme.lineSoft
                        : TokiburnTheme.accent.opacity(0.16 + intensity * 0.84)
            )
            .frame(width: cellSize, height: cellSize)
            .help(
                usage.map {
                    "\($0.date.formatted(date: .abbreviated, time: .omitted)) · \($0.totalTokens.formatted(.number.notation(.compactName))) tokens · \($0.totalCost.formCurrency)"
                } ?? date.formatted(date: .abbreviated, time: .omitted)
            )
            .accessibilityLabel(
                usage.map {
                    "\($0.date.formatted(date: .complete, time: .omitted)), \($0.totalTokens) tokens"
                } ?? "\(date.formatted(date: .complete, time: .omitted)), no activity"
            )
            .contextMenu {
                if let usage {
                    Button("Copy Day Value") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(usage.totalCost.formCurrency, forType: .string)
                    }
                } else {
                    Text("No recorded activity")
                }
            }
    }

    private func legendCell(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(TokiburnTheme.accent.opacity(opacity))
            .frame(width: 7, height: 7)
    }
}
