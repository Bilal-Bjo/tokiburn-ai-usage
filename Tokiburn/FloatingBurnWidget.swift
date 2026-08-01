import AppKit
import SwiftUI

enum BurnGlancePreference {
    static let storageKey = "showBurnGlanceWhenMinimized"
}

enum BurnPulseInterval: Int, CaseIterable, Identifiable {
    static let storageKey = "burnPulseIntervalMinutes"

    case off = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        case .thirtyMinutes: "30 min"
        }
    }

    var timeInterval: TimeInterval? {
        guard self != .off else { return nil }
        return TimeInterval(rawValue * 60)
    }

    static func stored(_ value: Int) -> BurnPulseInterval {
        BurnPulseInterval(rawValue: value) ?? .off
    }
}

struct BurnPulseChange: Equatable {
    let delta: Double
    let since: Date

    static func positive(previousCost: Double, newCost: Double, since: Date) -> BurnPulseChange? {
        let delta = newCost - previousCost
        guard delta >= 0.01 else { return nil }
        return BurnPulseChange(delta: delta, since: since)
    }

    var deltaLabel: String {
        if delta >= 1_000_000 {
            return "+$\(compact(delta / 1_000_000))M"
        }
        if delta >= 1_000 {
            return "+$\(compact(delta / 1_000))K"
        }
        return "+\(delta.formCurrency)"
    }

    var contextLabel: String {
        "SINCE \(since.formatted(date: .omitted, time: .shortened).uppercased())"
    }

    private func compact(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(0...1))
        )
    }
}

struct BurnGlanceMetrics: Equatable {
    let monthCost: Double
    let todayCost: Double
    let dailyAverage: Double
    let monthChangeFraction: Double?

    init(
        report: UsageReport,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        monthCost = report.cost(in: .month, now: now, calendar: calendar)
        todayCost = report.days
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .reduce(0) { $0 + $1.totalCost }

        let elapsedDays = max(calendar.component(.day, from: now), 1)
        dailyAverage = monthCost / Double(elapsedDays)
        monthChangeFraction = report
            .comparison(for: .month, now: now, calendar: calendar)?
            .changeFraction
    }

    var comparisonLabel: String {
        guard let monthChangeFraction else { return "No prior data" }
        return monthChangeFraction.formatted(
            .percent
                .precision(.fractionLength(0))
                .sign(strategy: .always())
        )
    }
}

@MainActor
final class BurnGlanceController: NSObject, ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var pulseChange: BurnPulseChange?
    @Published private(set) var lastPulseChange: BurnPulseChange?

    private weak var ownerWindow: NSWindow?
    private weak var model: AppModel?
    private var panel: BurnGlancePanel?
    private var observations: [NSObjectProtocol] = []
    private var isDismissedForCurrentMiniaturization = false
    private var pulseTimer: Timer?
    private var pulseDismissTask: Task<Void, Never>?

    private let collapsedSize = NSSize(width: 184, height: 46)
    private let expandedSize = NSSize(width: 254, height: 132)
    private let edgeInset: CGFloat = 18

    func attach(to window: NSWindow, model: AppModel) {
        guard ownerWindow !== window else { return }

        removeObservations()
        ownerWindow = window
        self.model = model

        let center = NotificationCenter.default
        observations = [
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.beginMiniaturizedSession() }
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.endMiniaturizedSession() }
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.positionPanel(animated: false) }
            },
            center.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.preferenceDidChange() }
            }
        ]

        if window.isMiniaturized {
            beginMiniaturizedSession()
        }
    }

    func toggleExpanded() {
        guard panel?.isVisible == true else { return }
        isExpanded.toggle()
        resizePanel(animated: true)
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        resizePanel(animated: true)
    }

    func dismissForNow() {
        isDismissedForCurrentMiniaturization = true
        hide()
    }

    func restoreTokiburn() {
        guard let ownerWindow else { return }
        hide()
        ownerWindow.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
        ownerWindow.makeKeyAndOrderFront(nil)
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: BurnGlancePreference.storageKey)
        hide()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: BurnGlancePreference.storageKey) as? Bool ?? true
    }

    private var pulseInterval: BurnPulseInterval {
        let stored = UserDefaults.standard.integer(forKey: BurnPulseInterval.storageKey)
        return BurnPulseInterval.stored(stored)
    }

    private func showIfNeeded() {
        guard
            isEnabled,
            !isDismissedForCurrentMiniaturization,
            let ownerWindow,
            ownerWindow.isMiniaturized,
            let model
        else {
            hide()
            return
        }

        isExpanded = false
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        panel.setContentSize(collapsedSize)
        positionPanel(animated: false)
        panel.orderFrontRegardless()
        schedulePulseTimer()
    }

    private func beginMiniaturizedSession() {
        isDismissedForCurrentMiniaturization = false
        lastPulseChange = nil
        showIfNeeded()
    }

    private func endMiniaturizedSession() {
        isDismissedForCurrentMiniaturization = false
        lastPulseChange = nil
        hide()
    }

    private func hide() {
        isExpanded = false
        pulseChange = nil
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseDismissTask?.cancel()
        pulseDismissTask = nil
        panel?.orderOut(nil)
    }

    private func preferenceDidChange() {
        if isEnabled {
            if panel?.isVisible == true {
                schedulePulseTimer()
            } else {
                showIfNeeded()
            }
        } else {
            hide()
        }
    }

    private func schedulePulseTimer() {
        pulseTimer?.invalidate()
        pulseTimer = nil

        guard
            panel?.isVisible == true,
            let timeInterval = pulseInterval.timeInterval
        else { return }

        let timer = Timer(timeInterval: timeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshForPulse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    private func refreshForPulse() async {
        guard
            panel?.isVisible == true,
            pulseInterval != .off,
            let model
        else { return }

        let previousCost = model.report.cost(in: .month)
        let since = model.report.loadedAt
        guard let refreshed = await model.refreshNow() else { return }
        guard panel?.isVisible == true, !refreshed.isDemo else { return }

        let newCost = refreshed.cost(in: .month)
        guard let change = BurnPulseChange.positive(
            previousCost: previousCost,
            newCost: newCost,
            since: since
        ) else { return }

        pulseDismissTask?.cancel()
        lastPulseChange = change
        pulseChange = change
        pulseDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pulseChange = nil
                self?.pulseDismissTask = nil
            }
        }
    }

    private func makePanel(model: AppModel) -> BurnGlancePanel {
        let panel = BurnGlancePanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = BurnGlanceHostingView(
            rootView: BurnGlanceView(model: model, controller: self)
        )
        return panel
    }

    private func resizePanel(animated: Bool) {
        guard let panel else { return }
        let targetSize = isExpanded ? expandedSize : collapsedSize
        let targetFrame = panelFrame(size: targetSize)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func positionPanel(animated: Bool) {
        guard let panel else { return }
        let targetSize = isExpanded ? expandedSize : collapsedSize
        let targetFrame = panelFrame(size: targetSize)

        if animated {
            panel.animator().setFrame(targetFrame, display: true)
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func panelFrame(size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        return NSRect(
            x: visibleFrame.minX + edgeInset,
            y: visibleFrame.minY + edgeInset,
            width: size.width,
            height: size.height
        )
    }

    private func removeObservations() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
    }

    deinit {
        observations.forEach(NotificationCenter.default.removeObserver)
    }
}

private final class BurnGlancePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class BurnGlanceHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private struct BurnGlanceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: BurnGlanceController

    @AppStorage(AppearanceMode.storageKey)
    private var appearanceValue = AppearanceMode.dark.rawValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceValue) ?? .dark
    }

    private var metrics: BurnGlanceMetrics {
        BurnGlanceMetrics(report: model.report)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: controller.toggleExpanded) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(TokiburnTheme.accent)
                            .frame(width: 3, height: 19)
                            .shadow(
                                color: TokiburnTheme.accent.opacity(controller.pulseChange == nil ? 0 : 0.55),
                                radius: controller.pulseChange == nil ? 0 : 5
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(metrics.monthCost.formCurrency)
                                .font(TokiburnTheme.display(16, weight: .semibold))
                                .foregroundStyle(TokiburnTheme.ink)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: metrics.monthCost))

                            Text(pulseSummary)
                                .font(TokiburnTheme.mono(8, weight: .semibold))
                                .tracking(controller.pulseChange == nil ? 0.7 : 0.25)
                                .foregroundStyle(
                                    controller.pulseChange == nil
                                        ? TokiburnTheme.tertiary
                                        : TokiburnTheme.accent
                                )
                                .contentTransition(.opacity)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: controller.isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TokiburnTheme.tertiary)
                    }
                    .padding(.leading, 13)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                    .background(isHovered ? TokiburnTheme.lineSoft.opacity(0.48) : .clear)
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .help(controller.isExpanded ? "Collapse Burn Glance" : "Expand Burn Glance")
                .accessibilityLabel(
                    "This month, \(metrics.monthCost.formCurrency). "
                    + (controller.isExpanded ? "Collapse Burn Glance" : "Expand Burn Glance")
                )

                Button(action: controller.dismissForNow) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(TokiburnTheme.tertiary)
                        .frame(width: 28, height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide until Tokiburn is minimized again")
                .accessibilityLabel("Hide Burn Glance until next minimize")
            }

            if controller.isExpanded {
                Rectangle()
                    .fill(TokiburnTheme.line)
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                HStack(spacing: 0) {
                    glanceMetric(title: "TODAY", value: metrics.todayCost.formCurrency)
                    glanceDivider
                    glanceMetric(title: "DAILY AVG", value: metrics.dailyAverage.formCurrency)
                    glanceDivider
                    glanceMetric(title: "VS PRIOR MTD", value: metrics.comparisonLabel)
                }
                .frame(height: 51)
                .padding(.horizontal, 12)

                HStack(spacing: 5) {
                    Image(systemName: controller.lastPulseChange == nil ? "lock.fill" : "arrow.up.right")
                        .font(.system(size: 8, weight: .semibold))
                    Text(expandedFooterLabel)
                    Spacer()
                    Text(model.report.loadedAt.formatted(date: .omitted, time: .shortened))
                }
                .font(TokiburnTheme.body(9, weight: .medium))
                .foregroundStyle(
                    controller.lastPulseChange == nil
                        ? TokiburnTheme.tertiary
                        : TokiburnTheme.accent
                )
                .padding(.horizontal, 13)
                .padding(.bottom, 9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(TokiburnTheme.surface)
                        : AnyShapeStyle(.ultraThinMaterial)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(TokiburnTheme.line.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(appearance == .dark ? 0.3 : 0.12), radius: 16, y: 7)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .preferredColorScheme(appearance.colorScheme)
        .animation(
            reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.96),
            value: controller.isExpanded
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18),
            value: controller.pulseChange
        )
        .contextMenu {
            Button("Open Tokiburn") {
                controller.restoreTokiburn()
            }

            Button("Hide for Now") {
                controller.dismissForNow()
            }

            Divider()

            Button("Turn Off Burn Glance") {
                controller.disable()
            }
        }
    }

    private var pulseSummary: String {
        guard let pulseChange = controller.pulseChange else {
            return "THIS MONTH"
        }
        return "\(pulseChange.deltaLabel) · \(pulseChange.contextLabel)"
    }

    private var expandedFooterLabel: String {
        guard let lastPulseChange = controller.lastPulseChange else {
            return "Local estimate"
        }
        return "\(lastPulseChange.deltaLabel) since "
            + lastPulseChange.since.formatted(date: .omitted, time: .shortened)
    }

    private func glanceMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TokiburnTheme.mono(7, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(TokiburnTheme.tertiary)
                .lineLimit(1)

            Text(value)
                .font(TokiburnTheme.mono(10, weight: .semibold))
                .foregroundStyle(TokiburnTheme.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var glanceDivider: some View {
        Rectangle()
            .fill(TokiburnTheme.line)
            .frame(width: 1, height: 26)
            .padding(.horizontal, 7)
    }
}

struct MainWindowReader: NSViewRepresentable {
    let onResolve: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReadingView {
        WindowReadingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: WindowReadingView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindow()
    }

    final class WindowReadingView: NSView {
        var onResolve: @MainActor (NSWindow) -> Void

        init(onResolve: @escaping @MainActor (NSWindow) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveWindow()
        }

        func resolveWindow() {
            guard let window else { return }
            Task { @MainActor in
                onResolve(window)
            }
        }
    }
}
