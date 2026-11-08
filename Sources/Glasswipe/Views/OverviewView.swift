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
                }

                smartScanCard

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach([Module.storage, .developer, .uninstaller, .leftovers, .spaceLens, .largeFiles, .startup, .memory]) { m in
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
        return Card {
            HStack(spacing: 18) {
                ZStack {
                    RingGauge(fraction: used, color: used > 0.9 ? .red : .accentColor)
                    Text("\(Int(used * 100))%").font(.title3.bold().monospacedDigit())
                }
                .frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage").font(.headline)
                    Text("\(free.formattedBytes) available").font(.title3.monospacedDigit())
                    Text("of \(total.formattedBytes)").foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var memoryCard: some View {
        let m = model.memory
        return Card {
            HStack(spacing: 18) {
                ZStack {
                    RingGauge(fraction: Double(m.pressurePercent) / 100, color: m.level.color)
                    Text("\(m.pressurePercent)%").font(.title3.bold().monospacedDigit())
                }
                .frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory pressure").font(.headline)
                    Text("\(m.used.formattedBytes) used").font(.title3.monospacedDigit())
                    Text("Swap \(m.swapUsed.formattedBytes) · Compressed \(m.compressed.formattedBytes)").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Free Up") { model.selection = .memory }.buttonStyle(.glass)
            }
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
            Text(module.title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}
