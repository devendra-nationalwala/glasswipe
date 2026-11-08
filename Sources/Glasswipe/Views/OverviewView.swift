import GlasswipeCore
import SwiftUI

/// Dashboard: disk, memory and a one-click Smart Scan across Junk modules.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var smartScanning = false

    var junkFound: Int64 { model.storage.totalSize + model.developer.totalSize }
    var hasScanned: Bool { model.storage.scannedAt != nil || model.developer.scannedAt != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(module: .overview, subtitle: "Your Mac at a glance")
                FullDiskAccessBanner()

                HStack(spacing: 16) {
                    diskCard
                    memoryCard
                    cpuCard
                }

                smartScanCard

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    ForEach([Module.storage, .developer, .uninstaller, .leftovers, .spaceLens, .largeFiles, .startup, .memory, .cpu]) { m in
                        Button { model.selection = m } label: { ModuleTile(module: m) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
    }

    private var diskCard: some View {
        let total = model.stats?.diskTotal ?? 1
        let free = model.stats?.diskFree ?? 0
        let used = Double(total - free) / Double(max(total, 1))
        return GaugeCard(title: "Storage", fraction: used, color: used > 0.9 ? .red : .accentColor, value: "\(Int(used * 100))%") {
            Text(free.formattedBytes).font(.headline.monospacedDigit())
            Text("free of \(total.formattedBytes)").foregroundStyle(.secondary)
        } action: {
            Button("Clean") { model.selection = .storage }
        }
    }

    private var memoryCard: some View {
        let m = model.memory
        return GaugeCard(title: "Memory", fraction: Double(m.pressurePercent) / 100, color: m.level.color,
                         value: "\(m.pressurePercent)%") {
            Text("\(m.used.formattedBytes) used").font(.headline.monospacedDigit())
            Text("Swap \(m.swapUsed.formattedBytes)").foregroundStyle(.secondary)
            Text(m.level.rawValue.capitalized).foregroundStyle(m.level.color)
        } action: {
            Button("Free Up") { model.selection = .memory }
        }
    }

    private var cpuCard: some View {
        let c = model.cpu
        return GaugeCard(title: "CPU", fraction: c.total / 100, color: CPUView.color(for: c.total), value: "\(Int(c.total))%") {
            Text("Load \(c.loadAverage.first.map { String(format: "%.2f", $0) } ?? "–")").font(.headline.monospacedDigit())
            Text("\(model.cpuInfo.logicalCores) cores").foregroundStyle(.secondary)
            Text(c.thermal.label).foregroundStyle(c.thermal.color)
        } action: {
            Button("Details") { model.selection = .cpu }
        }
    }

    private var smartScanCard: some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Scan").font(.title3.bold())
                    if smartScanning {
                        Text("Scanning System Junk and Developer Junk…").foregroundStyle(.secondary)
                    } else if hasScanned {
                        Text("\(junkFound.formattedBytes) of Junk found. Review it in Storage Cleaner and Developer Junk.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Finds caches, logs and Developer Junk you can safely remove.").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if smartScanning {
                    ProgressView().controlSize(.small)
                } else if hasScanned && junkFound > 0 {
                    Button("Review") { model.selection = model.storage.totalSize >= model.developer.totalSize ? .storage : .developer }
                        .buttonStyle(.glassProminent)
                } else {
                    Button("Scan") {
                        smartScanning = true
                        Task {
                            async let a: Void = model.storage.scan()
                            async let b: Void = model.developer.scan()
                            _ = await (a, b)
                            smartScanning = false
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        }
    }
}

/// Overview card: title and action on top, a ring gauge with details below.
struct GaugeCard<Details: View, Action: View>: View {
    let title: String
    let fraction: Double
    let color: Color
    let value: String
    @ViewBuilder var details: Details
    @ViewBuilder var action: Action

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    action.buttonStyle(.glass).controlSize(.small)
                }
                HStack(spacing: 14) {
                    ZStack {
                        RingGauge(fraction: fraction, color: color, lineWidth: 9)
                        Text(value).font(.headline.monospacedDigit())
                    }
                    .frame(width: 66, height: 66)
                    VStack(alignment: .leading, spacing: 2) { details }
                        .font(.callout)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 18))
    }
}

struct ModuleTile: View {
    let module: Module
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
            Text(module.title).font(.headline).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}
