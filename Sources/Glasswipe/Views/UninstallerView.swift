import AppKit
import GlasswipeCore
import SwiftUI

/// Lists installed apps; choosing one shows its App Footprint for review before Uninstall.
struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var apps: [InstalledApp] = []
    @State private var loading = false
    @State private var search = ""
    @State private var sort: Sort = .size
    @State private var selected: InstalledApp?
    @State private var session: ScanSession?
    @State private var confirming = false

    enum Sort: String, CaseIterable { case size = "Size", name = "Name", lastUsed = "Last Used" }

    var filtered: [InstalledApp] {
        let base = search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .size: return base.sorted { $0.size > $1.size }
        case .name: return base
        case .lastUsed: return base.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(module: .uninstaller, subtitle: "\(apps.count) apps · \(apps.reduce(0) { $0 + $1.size }.formattedBytes)")
                HStack {
                    TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) } }
                        .labelsHidden().fixedSize()
                }
                if loading && apps.isEmpty {
                    ScanningView(label: "Measuring installed apps…", fraction: 0.5)
                } else {
                    List(filtered, selection: Binding(get: { selected?.id }, set: { id in select(apps.first { $0.id == id }) })) { app in
                        AppRow(app: app).tag(app.id)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(width: 380)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task { if apps.isEmpty { await load() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(loading)
            }
        }
        .sheet(isPresented: $confirming) {
            if let session {
                CleanupConfirmation(items: session.selectedItems) { Task { await uninstall(session) } }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = selected, let session {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    FileIcon(url: app.url, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title2.bold())
                        Text("\(app.bundleID)\(app.version.map { " · version \($0)" } ?? "")").foregroundStyle(.secondary)
                        if let used = app.lastUsed {
                            Text("Last opened \(used.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                if app.isApple {
                    Label("This is an Apple app. macOS may reinstall it with the next update.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                switch session.phase {
                case .scanning(let label, let fraction):
                    ScanningView(label: label, fraction: fraction)
                case .cleaning(let fraction):
                    ScanningView(label: "Uninstalling…", fraction: fraction)
                case .done(let freed, let failed):
                    DoneBanner(freed: freed, failed: failed, results: session.lastResults) {
                        selected = nil; Task { await load() }
                    }
                default:
                    ResultsList(session: session)
                        .overlay(alignment: .bottom) {
                            ActionBar(
                                title: "\(session.selectedSize.formattedBytes) selected",
                                detail: "\(session.selectedItems.count) of \(session.items.count) items · name matches are unticked",
                                actionTitle: "Uninstall",
                                actionSymbol: "trash",
                                enabled: !session.selectedItems.isEmpty
                            ) { confirming = true } leading: { EmptyView() }
                        }
                }
            }
        } else {
            ContentUnavailableView("Choose an app", systemImage: "app.dashed",
                                   description: Text("Glasswipe shows the app and every file it created, so nothing is left behind."))
        }
    }

    private func select(_ app: InstalledApp?) {
        selected = app
        guard let app else { session = nil; return }
        let s = ScanSession(kind: .footprint(app))
        s.model = model
        session = s
        Task { await s.scan() }
    }

    private func load() async {
        loading = true
        apps = await AppInventory.scan().filter { !Demo.hides($0.name) && !Demo.hides($0.bundleID) }
        loading = false
        if Demo.isOn, selected == nil, let sample = apps.first(where: { ["us.zoom.xos", "com.tinyspeck.slackmacgap", "com.spotify.client"].contains($0.bundleID) }) {
            select(sample)
        }
    }

    private func uninstall(_ session: ScanSession) async {
        if case .footprint(let app) = session.kind {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
                running.terminate()
            }
            try? await Task.sleep(for: .seconds(1))
        }
        await session.clean()
    }
}

struct AppRow: View {
    let app: InstalledApp
    var body: some View {
        HStack(spacing: 10) {
            FileIcon(url: app.url, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.lastUsed.map { "Opened \($0.formatted(.relative(presentation: .named)))" } ?? "Never opened")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(app.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
