import AppKit
import GlasswipeCore
import SwiftUI

/// Every Cleanup, read from the JSON Lines log.
struct HistoryView: View {
    @State private var entries: [CleanupResult] = []

    var byDay: [(Date, [CleanupResult])] {
        Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModuleHeader(module: .history,
                         subtitle: "\(entries.filter(\.succeeded).reduce(0) { $0 + $1.size }.formattedBytes) freed in total")
            if entries.isEmpty {
                ContentUnavailableView("No cleanups yet", systemImage: "clock",
                                       description: Text("Everything Glasswipe removes is recorded here."))
            } else {
                List {
                    ForEach(byDay, id: \.0) { day, results in
                        Section(day.formatted(date: .complete, time: .omitted)) {
                            ForEach(results) { r in
                                HStack {
                                    Image(systemName: r.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(r.succeeded ? .green : .red)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.title)
                                        Text(r.error ?? "\(r.method) · \(r.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(r.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                                    Text(r.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            HStack {
                Spacer()
                Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }
                    .help("Items moved to the Trash can be put back from there")
                Button("Show Log File") { NSWorkspace.shared.activateFileViewerSelecting([CleanupLog.standard.url]) }
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .task { entries = CleanupLog.standard.read() }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                Section("Permissions") {
                    LabeledContent("Full Disk Access") {
                        HStack {
                            Text(model.hasFullDiskAccess ? "On" : "Off").foregroundStyle(model.hasFullDiskAccess ? .green : .orange)
                            Button("Open Settings") { FullDiskAccess.openSettings() }
                            Button("Check") { model.refreshAccess() }
                        }
                    }
                    Text("Full Disk Access is tied to how Glasswipe is signed. Build it with the same signing identity every time, or macOS will ask again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Memory") {
                    Toggle("Notify me when memory pressure is critical", isOn: $model.alertOnCriticalPressure)
                }
                Section("Safety") {
                    LabeledContent("Junk rules") {
                        Text(model.rules.map { "\($0.rules.count) rules loaded" } ?? "Not loaded — cleanup is disabled")
                            .foregroundStyle(model.rules == nil ? .red : .secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            ExclusionsSettings()
                .tabItem { Label("Exclusions", systemImage: "hand.raised") }
        }
        .frame(width: 520, height: 380)
    }
}

struct ExclusionsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Glasswipe never scans or removes anything inside these folders.").foregroundStyle(.secondary)
            List(model.exclusions, id: \.self, selection: $selection) { path in
                Label(path, systemImage: "folder")
            }
            HStack {
                Button { add() } label: { Image(systemName: "plus") }
                Button { if let s = selection { model.exclusions.removeAll { $0 == s } } } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
            }
        }
        .padding()
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.exclusions += panel.urls.map(\.path).filter { !model.exclusions.contains($0) }
        }
    }
}
