import SwiftUI

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(TokiburnTheme.mono(10, weight: .semibold))
            .tracking(1.45)
            .foregroundStyle(TokiburnTheme.secondary)
    }
}

struct PeriodSelector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(UsagePeriod.allCases) { period in
                Button {
                    model.select(period)
                } label: {
                    Text(period.shortTitle)
                        .font(TokiburnTheme.body(11, weight: .semibold))
                        .foregroundStyle(model.selectedPeriod == period ? TokiburnTheme.canvas : TokiburnTheme.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if model.selectedPeriod == period {
                                Capsule().fill(TokiburnTheme.ink)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(period.title.lowercased())")
            }
        }
        .padding(3)
        .background(TokiburnTheme.lineSoft)
        .clipShape(Capsule())
    }
}

struct MonthNavigator: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            navigationButton(
                systemName: "chevron.left",
                label: "Previous month",
                enabled: model.canSelectPreviousMonth
            ) {
                model.selectAdjacentMonth(-1)
            }

            Eyebrow(text: model.selectedMonthTitle)
                .contentTransition(.numericText())
                .frame(minWidth: 104)

            navigationButton(
                systemName: "chevron.right",
                label: "Next month",
                enabled: model.canSelectNextMonth
            ) {
                model.selectAdjacentMonth(1)
            }
        }
    }

    private func navigationButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? TokiburnTheme.secondary : TokiburnTheme.line)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct RefreshButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            model.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TokiburnTheme.ink)
                .frame(width: 28, height: 28)
                .background(TokiburnTheme.surface)
                .clipShape(Circle())
                .overlay { Circle().stroke(TokiburnTheme.line, lineWidth: 1) }
                .rotationEffect(.degrees(model.isRefreshing && !reduceMotion ? 360 : 0))
                .animation(
                    model.isRefreshing && !reduceMotion
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .default,
                    value: model.isRefreshing
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing)
        .help(model.isRefreshing ? "Reading local histories…" : "Refresh local usage")
    }
}

struct ProviderRow: View {
    let provider: ProviderUsage
    let totalCost: Double
    var compact = false

    private var share: Double {
        guard totalCost > 0 else { return 0 }
        return provider.cost / totalCost
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ProviderStyle.color(for: provider.agent))
                .frame(width: 8, height: 8)

            Text(ProviderStyle.name(for: provider.agent))
                .font(TokiburnTheme.body(12, weight: .medium))
                .foregroundStyle(TokiburnTheme.ink)
                .lineLimit(1)

            Spacer()

            Text(share, format: .percent.precision(.fractionLength(0)))
                .font(TokiburnTheme.mono(10, weight: .medium))
                .foregroundStyle(TokiburnTheme.tertiary)
                .frame(width: 34, alignment: .trailing)

            Text(provider.cost.formCurrency)
                .font(TokiburnTheme.mono(11, weight: .medium))
                .foregroundStyle(TokiburnTheme.secondary)
                .frame(width: compact ? 76 : 86, alignment: .trailing)
        }
        .frame(height: compact ? 23 : 20)
        .help(
            "\(provider.totalTokens.formatted(.number.notation(.compactName))) tokens · \(provider.cost.formCurrency)"
        )
    }
}

struct ProviderMix: View {
    let providers: [ProviderUsage]
    let totalCost: Double
    let totalTokens: Int

    @State private var showingAllProviders = false

    private var rows: [ProviderUsage] {
        providers.compacted(maximumRows: 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Eyebrow(text: "Agent mix")
                Spacer()

                if providers.count > 4 {
                    Button {
                        showingAllProviders = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(providers.count) sources")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .font(TokiburnTheme.mono(9, weight: .medium))
                        .foregroundStyle(TokiburnTheme.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show every source")
                    .accessibilityLabel("Show all \(providers.count) sources")
                    .popover(isPresented: $showingAllProviders, arrowEdge: .top) {
                        allProvidersPopover
                    }
                } else {
                    Text("\(providers.count) \(providers.count == 1 ? "source" : "sources")")
                        .font(TokiburnTheme.mono(9, weight: .medium))
                        .foregroundStyle(TokiburnTheme.tertiary)
                }
            }

            ProviderShareBar(providers: rows, totalCost: totalCost)

            VStack(spacing: 1) {
                ForEach(rows) { provider in
                    ProviderRow(provider: provider, totalCost: totalCost)
                }
            }
        }
    }

    private var allProvidersPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("All sources")
                    .font(TokiburnTheme.body(14, weight: .semibold))
                    .foregroundStyle(TokiburnTheme.ink)
                Text("\(totalTokens.formatted(.number.notation(.compactName))) tokens in this period")
                    .font(TokiburnTheme.body(10))
                    .foregroundStyle(TokiburnTheme.secondary)
            }

            Rectangle()
                .fill(TokiburnTheme.line)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(providers) { provider in
                        ProviderRow(provider: provider, totalCost: totalCost, compact: true)
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(16)
        .frame(
            width: 320,
            height: min(CGFloat(providers.count) * 25 + 90, 360)
        )
        .background(TokiburnTheme.surface)
    }
}

private struct ProviderShareBar: View {
    let providers: [ProviderUsage]
    let totalCost: Double

    private var totalTokens: Int {
        providers.reduce(0) { $0 + $1.totalTokens }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(providers) { provider in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ProviderStyle.color(for: provider.agent))
                        .frame(
                            width: max(
                                (proxy.size.width - CGFloat(max(providers.count - 1, 0)) * 2)
                                    * share(for: provider),
                                share(for: provider) > 0 ? 2 : 0
                            )
                        )
                        .help(
                            "\(ProviderStyle.name(for: provider.agent)) · \(share(for: provider), format: .percent.precision(.fractionLength(0)))"
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 6)
        .background(TokiburnTheme.lineSoft)
        .clipShape(Capsule())
        .accessibilityLabel("Agent cost distribution")
    }

    private func share(for provider: ProviderUsage) -> Double {
        if totalCost > 0 {
            return provider.cost / totalCost
        }
        guard totalTokens > 0 else { return 0 }
        return Double(provider.totalTokens) / Double(totalTokens)
    }
}

enum ProviderStyle {
    static func name(for agent: String) -> String {
        if agent.hasPrefix("Other ") { return agent }

        return switch agent.lowercased() {
        case "claude": "Claude"
        case "codex": "Codex"
        case "opencode": "OpenCode"
        case "amp": "Amp"
        case "droid": "Droid"
        case "codebuff": "Codebuff"
        case "hermes": "Hermes"
        case "pi": "Pi"
        case "goose": "Goose"
        case "openclaw": "OpenClaw"
        case "kilo": "Kilo"
        case "kimi": "Kimi"
        case "qwen": "Qwen"
        case "copilot": "Copilot"
        case "gemini": "Gemini"
        default: agent.capitalized
        }
    }

    static func color(for agent: String) -> Color {
        if agent.hasPrefix("Other ") { return TokiburnTheme.tertiary }

        return switch agent.lowercased() {
        case "codex": Color(hex: 0x6F7FD8)
        case "claude": Color(hex: 0xE18B62)
        case "opencode": Color(hex: 0x4F8292)
        case "amp": Color(hex: 0xA56BCE)
        case "droid": Color(hex: 0xC89A45)
        case "codebuff": Color(hex: 0xC96A75)
        case "hermes": Color(hex: 0x5F82C8)
        case "pi": Color(hex: 0x69A477)
        case "goose": Color(hex: 0x55A5A3)
        case "openclaw": Color(hex: 0xD47763)
        case "kilo": Color(hex: 0xB66FA1)
        case "kimi": Color(hex: 0x8D75B8)
        case "qwen": Color(hex: 0xB8944F)
        case "copilot": Color(hex: 0x71809A)
        case "gemini": Color(hex: 0x5D91CC)
        default: fallbackColors[stableIndex(for: agent)]
        }
    }

    private static let fallbackColors = [
        Color(hex: 0x7389B8),
        Color(hex: 0x6F9A83),
        Color(hex: 0xA27C9D),
        Color(hex: 0xA67D5D),
        Color(hex: 0x678F9B)
    ]

    private static func stableIndex(for agent: String) -> Int {
        agent.lowercased().unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) % fallbackColors.count
        }
    }
}

extension Double {
    var formCurrency: String {
        formatted(
            .currency(code: "USD")
                .locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(0...2))
        )
    }

    var formWholeCurrency: String {
        formatted(
            .currency(code: "USD")
                .locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(0))
        )
    }
}
