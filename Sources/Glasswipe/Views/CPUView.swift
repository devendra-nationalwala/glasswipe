import Charts
import GlasswipeCore
import SwiftUI

/// CPU: live load, every core, the chip, and which apps and processes keep it busy.
struct CPUView: View {
    @Environment(AppModel.self) private var model
    @State private var usage: [AppCPUUsage] = []
    @State private var sampler = AppCPUSampler()
    @State private var measured = false
    @State private var forceQuitTarget: AppCPUUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(module: .cpu, subtitle: "\(model.cpuInfo.name) · \(coresText)")
            HStack(spacing: 16) {
                loadCard
                historyCard
            }
            HStack(alignment: .top, spacing: 16) {
                coresCard
                detailsCard.frame(width: 260)
            }
            HStack {
                Text("Apps and processes by CPU").font(.headline)
                Spacer()
                Text("100% = one full core, as in Activity Monitor").font(.caption).foregroundStyle(.secondary)
            }
            processList
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .task { await refreshLoop() }
        .confirmationDialog("Force quit \(forceQuitTarget?.name ?? "")?", isPresented: Binding(
            get: { forceQuitTarget != nil }, set: { if !$0 { forceQuitTarget = nil } })) {
            Button("Force Quit", role: .destructive) {
                if let t = forceQuitTarget { Task { _ = await AppMemory.perform(.forceQuit, on: t.pid); await refresh() } }
            }
        } message: {
            Text("Unsaved changes will be lost.")
        }
    }

    private var coresText: String {
        let info = model.cpuInfo
        guard info.performanceCores > 0, info.efficiencyCores > 0 else { return "\(info.logicalCores) cores" }
        return "\(info.performanceCores) performance + \(info.efficiencyCores) efficiency cores"
    }

    private var loadCard: some View {
        let c = model.cpu
        return Card {
            HStack(spacing: 16) {
                ZStack {
                    RingGauge(fraction: c.total / 100, color: Self.color(for: c.total), lineWidth: 10)
                    VStack(spacing: 0) {
                        Text("\(Int(c.total))%").font(.title3.bold().monospacedDigit())
                        Text("in use").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    row("User", String(format: "%.1f%%", c.user), .blue)
                    row("System", String(format: "%.1f%%", c.system), .red)
                    row("Idle", String(format: "%.1f%%", max(0, 100 - c.total)), .secondary)
                }
                .font(.callout)
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("CPU load").font(.headline)
                Chart(Array(model.cpuHistory.enumerated()), id: \.offset) { index, s in
                    AreaMark(x: .value("t", index), y: .value("percent", s.system), stacking: .standard)
                        .foregroundStyle(by: .value("kind", "System"))
                    AreaMark(x: .value("t", index), y: .value("percent", s.user), stacking: .standard)
                        .foregroundStyle(by: .value("kind", "User"))
                }
                .chartForegroundStyleScale(["System": Color.red.opacity(0.7), "User": Color.blue.opacity(0.7)])
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 80)
            }
        }
    }

    private var coresCard: some View {
        let cores = model.cpu.cores
        let efficiency = model.cpuInfo.efficiencyCores
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cores").font(.headline)
                    Spacer()
                    if efficiency > 0 && model.cpuInfo.performanceCores > 0 {
                        Label("Efficiency", systemImage: "leaf.fill").foregroundStyle(.green)
                        Label("Performance", systemImage: "bolt.fill").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(cores.enumerated()), id: \.offset) { index, load in
                        // Apple silicon numbers its efficiency cores first.
                        let isEfficiency = index < efficiency && model.cpuInfo.performanceCores > 0
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill((isEfficiency ? Color.green : Color.orange).gradient)
                                        .frame(height: geo.size.height * max(0.02, load / 100))
                                }
                            }
                            .animation(.smooth, value: load)
                            Text("\(Int(load))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .help("Core \(index + 1): \(Int(load))%")
                    }
                }
                .frame(height: 96)
            }
        }
    }

    private var detailsCard: some View {
        let c = model.cpu
        return Card {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Load average").foregroundStyle(.secondary)
                    Text(c.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  ")).monospacedDigit()
                }
                GridRow {
                    Text("Temperature").foregroundStyle(.secondary)
                    Text(c.thermal.label).foregroundStyle(c.thermal.color)
                }
                GridRow {
                    Text("Uptime").foregroundStyle(.secondary)
                    Text(Duration.seconds(c.uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
                }
                GridRow {
                    Text("Logical cores").foregroundStyle(.secondary)
                    Text("\(model.cpuInfo.logicalCores)").monospacedDigit()
                }
            }
            .font(.callout)
            .help("Load average is the number of threads waiting to run over the last 1, 5 and 15 minutes. Below the number of cores is comfortable.")
        }
    }

    private var processList: some View {
        List(usage.prefix(40)) { row in
            HStack(spacing: 10) {
                FileIcon(url: row.isApp ? URL(fileURLWithPath: row.path) : nil, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                    Text(row.processCount > 1 ? "\(row.processCount) processes" : (row.canQuit ? "App" : "Background process"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(measured ? String(format: "%.1f%%", row.percent) : "–")
                    .monospacedDigit()
                    .foregroundStyle(row.percent >= 80 ? .orange : .secondary)
                Menu {
                    Button("Quit") { Task { _ = await AppMemory.perform(.quit, on: row.pid); await refresh() } }
                    Divider()
                    Button("Force Quit…", role: .destructive) { forceQuitTarget = row }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .opacity(row.canQuit ? 1 : 0)
                .disabled(!row.canQuit)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(measured ? 2 : 1))
        }
    }

    private func refresh() async {
        if Demo.isOn {
            usage = Demo.cpuApps
            measured = true
            return
        }
        let rows = sampler.sample()
        // The first reading has nothing to compare with; keep the list until real percentages arrive.
        if measured || usage.isEmpty { usage = rows }
        if !measured && !usage.isEmpty && rows.contains(where: { $0.percent > 0 }) {
            usage = rows
            measured = true
        }
    }

    static func color(for percent: Double) -> Color {
        percent >= 85 ? .red : percent >= 60 ? .orange : .blue
    }

    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        GridRow {
            Label { Text(label).foregroundStyle(.secondary) } icon: { Circle().fill(color).frame(width: 7, height: 7) }
            Text(value).monospacedDigit()
        }
    }
}

extension CPUSnapshot.Thermal {
    var label: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot, slowing down"
        case .critical: "Very hot, slowed down"
        }
    }

    var color: Color {
        switch self {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        }
    }
}
