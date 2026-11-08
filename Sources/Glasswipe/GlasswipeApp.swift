import AppKit
import GlasswipeCore
import SwiftUI

@main
struct GlasswipeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() {
        if let kind = Report.requested { Report.run(kind) }
    }

    var body: some Scene {
        Window("Glasswipe", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 720)
        // Always open the window at launch, even if it was closed when the app last quit.
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Smart Scan") {
                    model.selection = .overview
                    Task {
                        async let a: Void = model.storage.scan()
                        async let b: Void = model.developer.scan()
                        _ = await (a, b)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Glasswipe") { Project.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Button("Star Glasswipe on GitHub…") { Project.star() }
                Button("Buy Me a Coffee…") { Project.buyCoffee() }
                Button("Report a Problem…") { NSWorkspace.shared.open(Project.issues) }
                Button("Check for Updates…") { NSWorkspace.shared.open(Project.releases) }
                Divider()
                Button("Glasswipe on GitHub") { NSWorkspace.shared.open(Project.repository) }
            }
            CommandMenu("Go") {
                ForEach(Array(Module.allCases.enumerated()), id: \.element) { index, module in
                    Button(module.title) { model.selection = module }
                        .keyboardShortcut(index < 9 ? KeyEquivalent(Character(String(index + 1))) : "0", modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: "sparkles")
            Text("\(model.memory.pressurePercent)%")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keep running in the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(Module.sections, id: \.1) { title, modules in
                    Section(title) {
                        ForEach(modules) { module in
                            Label(module.title, systemImage: module.symbol).tag(module)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        StarButton()
                        CoffeeButton(compact: true)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    AuthorCredit()
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
        } detail: {
            detail(for: model.selection ?? .overview)
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
        .task {
            if let folder = Snapshot.folder { await Snapshot.run(model, into: folder) }
        }
    }

    @ViewBuilder private func detail(for module: Module) -> some View {
        switch module {
        case .overview:
            OverviewView()
        case .storage:
            CleanerView(module: .storage, subtitle: "Caches, logs, temporary files, browser caches and the Trash",
                        explanation: "Find caches, logs and temporary files that apps recreate on their own.",
                        session: model.storage)
        case .developer:
            CleanerView(module: .developer, subtitle: "Build products, dependency folders and package-manager caches",
                        explanation: "Find Xcode build data, node_modules, and caches from npm, pip, uv, Homebrew, Docker and more.",
                        session: model.developer)
        case .memory:
            MemoryCleanerView()
        case .uninstaller:
            UninstallerView()
        case .leftovers:
            CleanerView(module: .leftovers, subtitle: "Files left behind by apps you already deleted",
                        explanation: "Find preferences, caches and containers belonging to apps that are no longer installed. Nothing is ticked until you choose it.",
                        session: model.leftovers)
        case .startup:
            StartupItemsView()
        case .spaceLens:
            SpaceLensView()
        case .largeFiles:
            CleanerView(module: .largeFiles, subtitle: "Files over 100 MB, or untouched for a year",
                        explanation: "Find big and forgotten files in your folders. Everything goes to the Trash, so you can change your mind.",
                        session: model.largeFiles)
        case .history:
            HistoryView()
        }
    }
}

/// Menu bar monitor: pressure, CPU, disk, battery, quick actions.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let m = model.memory
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("Glasswipe").font(.headline)
                Spacer()
                CoffeeButton(compact: true).buttonStyle(.borderless)
                StarButton(compact: true).buttonStyle(.borderless)
            }
            HStack(spacing: 12) {
                meter("Memory", value: Double(m.pressurePercent) / 100, text: "\(m.pressurePercent)%", color: m.level.color)
                meter("CPU", value: (model.stats?.cpuPercent ?? 0) / 100, text: "\(Int(model.stats?.cpuPercent ?? 0))%", color: .blue)
                if let stats = model.stats {
                    let used = 1 - Double(stats.diskFree) / Double(max(stats.diskTotal, 1))
                    meter("Disk", value: used, text: stats.diskFree.formattedBytes, color: .indigo)
                    if let battery = stats.batteryPercent {
                        meter("Battery", value: Double(battery) / 100, text: "\(battery)%\(stats.isCharging ? "⚡︎" : "")", color: .green)
                    }
                }
            }
            Text("Swap \(m.swapUsed.formattedBytes) · Compressed \(m.compressed.formattedBytes)")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Free Up Memory") { show(.memory) }.buttonStyle(.glass)
                Button("Smart Scan") { show(.overview) }.buttonStyle(.glassProminent)
            }
            HStack {
                Button("Open Glasswipe") { show(.overview) }.buttonStyle(.borderless)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func meter(_ label: String, value: Double, text: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RingGauge(fraction: value, color: color, lineWidth: 6)
                Text(text).font(.caption2.bold().monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1).padding(6)
            }
            .frame(width: 56, height: 56)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func show(_ module: Module) {
        model.selection = module
        openWindow(id: "main")
        NSApp.activate()
    }
}
