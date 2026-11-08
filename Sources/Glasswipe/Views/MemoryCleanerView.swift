import Charts
import GlasswipeCore
import SwiftUI

/// Memory Cleaner: real pressure, apps by footprint, Quit / Relaunch / Force Quit, Free Up Memory.
struct MemoryCleanerView: View {
    @Environment(AppModel.self) private var model
    @State private var apps: [AppMemoryUsage] = []
    @State private var selection: Set<pid_t> = []
    @State private var confirmFreeUp = false
    @State private var forceQuitTarget: AppMemoryUsage?
    @State private var before: MemorySnapshot?
    @State private var after: MemorySnapshot?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(module: .memory, subtitle: "Free memory by closing what holds it")
            gauges
            if let before, let after { BeforeAfter(before: before, after: after) }
            HStack {
                Text("Apps by memory").font(.headline)
                Spacer()
                Button("Select background apps over 500 MB") {
                    selection = Set(apps.filter { $0.isBackgroundCandidate && $0.footprint >= 500 * 1_048_576 }.map(\.pid))
                }
                .buttonStyle(.borderless)
            }
            appList
            Text("Glasswipe frees memory by quitting apps you choose. It has no “purge” button, because emptying macOS's file cache doesn't relieve memory pressure.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 72)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .overlay(alignment: .bottom) {
            let chosen = apps.filter { selection.contains($0.pid) }
            ActionBar(
                title: "\(chosen.reduce(UInt64(0)) { $0 + $1.footprint }.formattedBytes) selected",
                detail: "\(chosen.count) apps will be asked to quit",
                actionTitle: "Free Up Memory",
                actionSymbol: "memorychip",
                enabled: !chosen.isEmpty && !working
            ) { confirmFreeUp = true } leading: { EmptyView() }
        }
        .task { await refreshLoop() }
        .confirmationDialog("Quit \(selection.count) apps?", isPresented: $confirmFreeUp) {
            Button("Quit Apps") { Task { await freeUp() } }
        } message: {
            Text("Apps will be asked to quit normally, so they can save your work.")
        }
        .confirmationDialog("Force quit \(forceQuitTarget?.name ?? "")?", isPresented: Binding(
            get: { forceQuitTarget != nil }, set: { if !$0 { forceQuitTarget = nil } })) {
            Button("Force Quit", role: .destructive) {
                if let t = forceQuitTarget { Task { _ = await AppMemory.perform(.forceQuit, on: t.pid); await refresh() } }
            }
        } message: {
            Text("Unsaved changes will be lost.")
        }
    }

    private var gauges: some View {
        let m = model.memory
        return HStack(spacing: 16) {
            Card {
                HStack(spacing: 16) {
                    ZStack {
                        RingGauge(fraction: Double(m.pressurePercent) / 100, color: m.level.color, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text("\(m.pressurePercent)%").font(.title3.bold().monospacedDigit())
                            Text(m.level.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        stat("App memory", m.app)
                        stat("Wired", m.wired)
                        stat("Compressed", m.compressed)
                        stat("Swap used", m.swapUsed)
                        stat("Cached files", m.cached)
                    }
                    .font(.callout)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Memory pressure").font(.headline)
                    Chart(Array(model.memoryHistory.enumerated()), id: \.offset) { index, s in
                        AreaMark(x: .value("t", index), y: .value("pressure", s.pressurePercent))
                            .foregroundStyle(s.level.color.gradient.opacity(0.5))
                        LineMark(x: .value("t", index), y: .value("pressure", s.pressurePercent))
                            .foregroundStyle(s.level.color)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .frame(height: 80)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: UInt64) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value.formattedBytes).monospacedDigit()
        }
    }

    private var appList: some View {
        List(apps) { app in
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { selection.contains(app.pid) },
                    set: { if $0 { selection.insert(app.pid) } else { selection.remove(app.pid) } }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .disabled(!app.isBackgroundCandidate)
                FileIcon(url: app.bundleURL, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.processCount > 1 ? "\(app.processCount) processes" : (app.isActive ? "Active" : "Background"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(app.footprint.formattedBytes).monospacedDigit()
                    .foregroundStyle(app.footprint > 2 * 1_073_741_824 ? .orange : .secondary)
                Menu {
                    Button("Quit") { Task { _ = await AppMemory.perform(.quit, on: app.pid); await refresh() } }
                    Button("Relaunch") { Task { _ = await AppMemory.perform(.relaunch, on: app.pid); await refresh() } }
                    Divider()
                    Button("Force Quit…", role: .destructive) { forceQuitTarget = app }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!app.isBackgroundCandidate && !app.isActive)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func refresh() async {
        apps = Demo.isOn ? Demo.memoryApps : AppMemory.usage()
        selection = selection.intersection(Set(apps.map(\.pid)))
        if Demo.isOn && selection.isEmpty {
            selection = Set(apps.filter { $0.isBackgroundCandidate && $0.footprint >= 500 * 1_048_576 }.map(\.pid))
        }
    }

    private func freeUp() async {
        working = true
        before = MemorySampler.sample()
        after = nil
        for pid in selection { _ = await AppMemory.perform(.quit, on: pid) }
        selection = []
        try? await Task.sleep(for: .seconds(4))
        after = MemorySampler.sample()
        await refresh()
        working = false
    }
}

/// The real change after Free Up Memory, not a vanity number.
struct BeforeAfter: View {
    let before: MemorySnapshot
    let after: MemorySnapshot

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
            change("Pressure", "\(before.pressurePercent)% → \(after.pressurePercent)%")
            change("App memory", "\(before.app.formattedBytes) → \(after.app.formattedBytes)")
            change("Compressed", "\(before.compressed.formattedBytes) → \(after.compressed.formattedBytes)")
            change("Swap", "\(before.swapUsed.formattedBytes) → \(after.swapUsed.formattedBytes)")
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular.tint(.green.opacity(0.1)), in: .rect(cornerRadius: 14))
    }

    private func change(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }
}
