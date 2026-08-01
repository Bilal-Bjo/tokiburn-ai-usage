import AppKit
import SwiftUI

@main
struct TokiburnApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var burnGlanceController = BurnGlanceController()
    @AppStorage(AppearanceMode.storageKey) private var appearanceValue = AppearanceMode.dark.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceValue) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1_020, minHeight: 700)
                .preferredColorScheme(appearance.colorScheme)
                .background {
                    MainWindowReader { window in
                        burnGlanceController.attach(to: window, model: model)
                    }
                }
        }
        .defaultSize(width: 1_240, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("Period") {
                ForEach(Array(UsagePeriod.allCases.enumerated()), id: \.element.id) { index, period in
                    Button(period.title) {
                        model.select(period)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }

            CommandMenu("Data") {
                Button("Refresh Usage") {
                    NotificationCenter.default.post(name: .refreshUsage, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Show Archive in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([UsageArchive.defaultURL])
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!FileManager.default.fileExists(atPath: UsageArchive.defaultURL.path))
            }

            CommandMenu("Appearance") {
                Button(appearance == .dark ? "Use Light Appearance" : "Use Dark Appearance") {
                    appearanceValue = appearance.toggled.rawValue
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

private struct SettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceValue = AppearanceMode.dark.rawValue
    @AppStorage(BurnGlancePreference.storageKey) private var showBurnGlance = true
    @AppStorage(BurnPulseInterval.storageKey) private var burnPulseMinutes = BurnPulseInterval.off.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tokiburn Settings")
                    .font(TokiburnTheme.display(20, weight: .semibold))
                Text("Keep the dashboard comfortable without changing how your usage is read.")
                    .font(TokiburnTheme.body(11))
                    .foregroundStyle(TokiburnTheme.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance")
                        .font(TokiburnTheme.body(12, weight: .semibold))
                    Text("Choose the dashboard’s color scheme.")
                        .font(TokiburnTheme.body(10))
                        .foregroundStyle(TokiburnTheme.secondary)
                }

                Spacer()

                Picker("Appearance", selection: $appearanceValue) {
                    Text("Light").tag(AppearanceMode.light.rawValue)
                    Text("Dark").tag(AppearanceMode.dark.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Private archive")
                        .font(TokiburnTheme.body(12, weight: .semibold))
                    Text("Daily aggregates stored locally on this Mac.")
                        .font(TokiburnTheme.body(10))
                        .foregroundStyle(TokiburnTheme.secondary)
                }

                Spacer()

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([UsageArchive.defaultURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: UsageArchive.defaultURL.path))
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Burn Glance")
                        .font(TokiburnTheme.body(12, weight: .semibold))
                    Text("Show a private spend glance when Tokiburn is minimized.")
                        .font(TokiburnTheme.body(10))
                        .foregroundStyle(TokiburnTheme.secondary)
                }

                Spacer()

                Toggle("Show Burn Glance", isOn: $showBurnGlance)
                    .labelsHidden()
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live updates")
                        .font(TokiburnTheme.body(12, weight: .semibold))
                    Text("Refresh only while Burn Glance is visible.")
                        .font(TokiburnTheme.body(10))
                        .foregroundStyle(TokiburnTheme.secondary)
                }

                Spacer()

                Picker("Live updates", selection: $burnPulseMinutes) {
                    ForEach(BurnPulseInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 96)
                .disabled(!showBurnGlance)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(TokiburnTheme.canvas)
        .foregroundStyle(TokiburnTheme.ink)
    }
}

extension Notification.Name {
    static let refreshUsage = Notification.Name("com.bilal.tokiburn.refreshUsage")
}
