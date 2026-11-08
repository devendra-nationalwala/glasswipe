import AppKit
import GlasswipeCore
import SwiftUI

/// Large header used at the top of each module.
struct ModuleHeader: View {
    let module: Module
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: module.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Starting screen for a module before its first Scan.
struct ScanPrompt: View {
    let module: Module
    let explanation: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: module.symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text(explanation)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Button(action: action) {
                Label("Scan", systemImage: "magnifyingglass").font(.title3.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScanningView: View {
    let label: String
    let fraction: Double

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.large)
            Text(label.isEmpty ? "Scanning…" : label).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Floating glass bar with the selection total and the prominent action.
struct ActionBar<Leading: View>: View {
    let title: String
    let detail: String
    let actionTitle: String
    let actionSymbol: String
    let enabled: Bool
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline.monospacedDigit())
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSymbol).font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!enabled)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

/// Row with a checkbox for one Scan item.
struct ScanItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(item.inUseBy != nil)
            FileIcon(url: item.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                HStack(spacing: 6) {
                    if let busy = item.inUseBy {
                        Label("In use by \(AppNames.name(forBundleID: busy))", systemImage: "lock.fill").foregroundStyle(.orange)
                    } else if let note = item.note {
                        Text(note)
                    }
                    if item.tier == .caution { TierBadge(tier: item.tier) }
                    Text(item.method.label).foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text(item.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
            if let url = item.url {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .padding(.vertical, 2)
    }
}

struct TierBadge: View {
    let tier: Tier
    var body: some View {
        Text(tier == .caution ? "Review" : "Safe")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tier == .caution ? Color.orange.opacity(0.2) : Color.green.opacity(0.2), in: .capsule)
            .foregroundStyle(tier == .caution ? .orange : .green)
    }
}

struct FileIcon: View {
    let url: URL?
    var size: CGFloat = 22
    var body: some View {
        Group {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "terminal").resizable().scaledToFit().padding(3).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Grouped, checkable results for any ScanSession.
struct ResultsList: View {
    @Bindable var session: ScanSession

    var body: some View {
        List {
            ForEach(session.groups, id: \.0) { group in
                Section {
                    ForEach(group.1) { item in
                        ScanItemRow(item: item, isSelected: session.selection.contains(item.id)) { session.toggle(item) }
                    }
                } header: {
                    GroupHeader(title: group.0, items: group.1, session: session)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, 80)
    }
}

struct GroupHeader: View {
    let title: String
    let items: [ScanItem]
    @Bindable var session: ScanSession

    var allSelected: Bool { items.filter { $0.inUseBy == nil }.allSatisfy { session.selection.contains($0.id) } }

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { allSelected }, set: { session.setGroup(items, selected: $0) })) {
                Text(AppNames.name(forBundleID: title)).font(.headline)
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text("\(items.count) items · \(items.reduce(0) { $0 + $1.size }.formattedBytes)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Confirmation before anything is removed.
struct CleanupConfirmation: View {
    let items: [ScanItem]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var trashed: [ScanItem] { items.filter { $0.method == .trash } }
    var deleted: [ScanItem] { items.filter { $0.method == .delete || $0.method == .adminDelete } }
    var commands: [ScanItem] { items.filter { if case .toolCommand = $0.method { true } else { false } } }
    var needsAdmin: Bool { items.contains { $0.method == .adminDelete } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Clean up \(items.reduce(0) { $0 + $1.size }.formattedBytes)?", systemImage: "sparkles")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                if !deleted.isEmpty {
                    Label("\(deleted.count) items will be deleted. Their owners recreate them as needed.", systemImage: "trash")
                }
                if !trashed.isEmpty {
                    Label("\(trashed.count) items will be moved to the Trash, so you can put them back.", systemImage: "arrow.uturn.backward")
                }
                if !commands.isEmpty {
                    Label("\(commands.count) tools will clean up with their own commands.", systemImage: "terminal")
                }
                if needsAdmin {
                    Label("macOS will ask for your administrator password once.", systemImage: "lock.shield").foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clean Up") { dismiss(); onConfirm() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// Summary after a Cleanup.
struct DoneBanner: View {
    let freed: Int64
    let failed: Int
    let results: [CleanupResult]
    let again: () -> Void
    @State private var showFailures = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("Freed \(freed.formattedBytes)").font(.largeTitle.bold())
            if failed > 0 {
                Button("\(failed) items could not be removed") { showFailures = true }.buttonStyle(.link)
            }
            Button("Scan Again", action: again).buttonStyle(.glass).controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showFailures) {
            List(results.filter { !$0.succeeded }) { r in
                VStack(alignment: .leading) {
                    Text(r.title).bold()
                    Text(r.error ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 420, height: 260)
        }
    }
}

/// Banner asking for Full Disk Access when it is missing.
struct FullDiskAccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.hasFullDiskAccess && !Demo.isOn {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access is off").font(.headline)
                    Text("Glasswipe can't see the Trash, Safari, Mail or iOS backups until you allow it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") { FullDiskAccess.openSettings() }.buttonStyle(.glass)
                Button("Check Again") { model.refreshAccess() }.buttonStyle(.borderless)
            }
            .padding(12)
            .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 14))
        }
    }
}

/// Ring gauge used for disk and memory.
struct RingGauge: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: fraction)
        }
    }
}

extension UInt64 {
    var formattedBytes: String { Int64(clamping: self).formattedBytes }
}

extension MemorySnapshot.PressureLevel {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
