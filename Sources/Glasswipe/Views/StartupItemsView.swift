import AppKit
import GlasswipeCore
import SwiftUI

/// Launch agents and daemons, with persistent enable/disable and removal of broken items.
struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var error: String?
    @State private var removing: StartupItem?
    @State private var showApple = false

    var visible: [StartupItem] { showApple ? items : items.filter { !$0.label.hasPrefix("com.apple.") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModuleHeader(module: .startup, subtitle: "Things that start automatically when you log in or boot")
            HStack {
                Toggle("Show Apple items", isOn: $showApple).toggleStyle(.switch).controlSize(.small)
                Spacer()
                Button("Open Login Items Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
                .buttonStyle(.glass)
                .help("Apps that open at login are managed in System Settings")
            }
            List {
                ForEach(StartupItem.Scope.allCases, id: \.self) { scope in
                    let group = visible.filter { $0.scope == scope }
                    if !group.isEmpty {
                        Section(scope.rawValue + (scope.needsAdmin ? " · needs admin password" : "")) {
                            ForEach(group) { item in row(item) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .task { reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .alert("Couldn't change the item", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .confirmationDialog("Remove \(removing?.label ?? "")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let item = removing { run { try StartupItems.remove(item) } }
            }
        } message: { Text("It stops launching and its file goes to the Trash.") }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ownerName(item)).lineLimit(1)
                    if item.isBroken {
                        Text("Broken").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.red.opacity(0.18), in: .capsule).foregroundStyle(.red)
                    }
                }
                Text(item.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let program = item.program {
                    Text(program).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if item.isBroken {
                Button("Remove…") { removing = item }.buttonStyle(.borderless)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
            Toggle("", isOn: Binding(get: { item.isEnabled }, set: { on in run { try StartupItems.setEnabled(on, for: item) } }))
                .toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func ownerName(_ item: StartupItem) -> String {
        // com.vendor.app.agent → look up com.vendor.app, then com.vendor
        let parts = item.label.split(separator: ".")
        for n in stride(from: parts.count, through: 2, by: -1) {
            let id = parts.prefix(n).joined(separator: ".")
            let name = AppNames.name(forBundleID: id)
            if name != id { return name }
        }
        return item.label
    }

    private func reload() {
        items = Demo.isOn ? Demo.startupItems : StartupItems.scan()
    }

    private func run(_ change: @escaping @Sendable () throws -> Void) {
        Task {
            let message: String? = await Task.detached {
                do { try change(); return nil } catch { return error.localizedDescription }
            }.value
            if let message { error = message }
            reload()
        }
    }
}
