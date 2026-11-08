import AppKit
import GlasswipeCore
import SwiftUI

/// Space Lens: a drill-down treemap of what is using the disk.
struct SpaceLensView: View {
    @State private var path: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @State private var nodes: [SpaceNode] = []
    @State private var loading = false
    @State private var hovered: SpaceNode?
    @State private var trashTarget: SpaceNode?
    @Environment(AppModel.self) private var model

    var current: URL { path.last! }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(module: .spaceLens, subtitle: "See what's taking up space, then dig in")
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.offset) { index, url in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    Button(index == 0 ? "Home" : url.lastPathComponent) {
                        path = Array(path.prefix(index + 1))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                Spacer()
                Menu("Location") {
                    Button("Home") { path = [FileManager.default.homeDirectoryForCurrentUser] }
                    Button("Applications") { path = [URL(fileURLWithPath: "/Applications")] }
                    Button("Whole disk") { path = [URL(fileURLWithPath: "/")] }
                    Button("Choose Folder…") { chooseFolder() }
                }
                .fixedSize()
            }
            ZStack {
                if loading {
                    ScanningView(label: "Measuring \(current.lastPathComponent)…", fraction: 0.5)
                } else if nodes.isEmpty {
                    ContentUnavailableView("Empty or not readable", systemImage: "folder",
                                           description: Text(model.hasFullDiskAccess ? "" : "Full Disk Access may be needed."))
                } else {
                    Treemap(nodes: Array(nodes.prefix(60)), hovered: $hovered) { node in
                        if node.isDirectory { path.append(node.url) } else { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                    } trash: { trashTarget = $0 }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if let hovered {
                    Text(hovered.name).bold()
                    Text(hovered.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                    Text(hovered.isDirectory ? "Click to open" : "Click to show in Finder").foregroundStyle(.tertiary)
                } else {
                    Text("\(nodes.reduce(0) { $0 + $1.size }.formattedBytes) in \(current.path)").foregroundStyle(.secondary)
                }
                Spacer()
                Text("Right-click an item to move it to the Trash.").font(.caption).foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .task(id: current) { await load() }
        .confirmationDialog("Move \(trashTarget?.name ?? "") to the Trash?", isPresented: Binding(
            get: { trashTarget != nil }, set: { if !$0 { trashTarget = nil } })) {
            Button("Move to Trash", role: .destructive) { if let t = trashTarget { trash(t) } }
        } message: { Text(trashTarget.map { "\($0.size.formattedBytes). You can put it back from the Trash." } ?? "") }
    }

    private func load() async {
        loading = true
        nodes = await SpaceLens.children(of: current)
        loading = false
    }

    private func trash(_ node: SpaceNode) {
        guard model.gate.forUninstall.allows(node.url) else { return }
        try? FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        nodes.removeAll { $0.id == node.id }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { path = [url] }
    }
}

/// Squarified treemap.
struct Treemap: View {
    let nodes: [SpaceNode]
    @Binding var hovered: SpaceNode?
    let open: (SpaceNode) -> Void
    let trash: (SpaceNode) -> Void

    var body: some View {
        GeometryReader { geo in
            let rects = TreemapLayout.squarify(sizes: nodes.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(nodes, rects)), id: \.0.id) { node, rect in
                    tile(node, rect: rect)
                }
            }
        }
    }

    private func tile(_ node: SpaceNode, rect: CGRect) -> some View {
        let color = Self.color(for: node)
        return RoundedRectangle(cornerRadius: 8)
            .fill(color.gradient.opacity(hovered?.id == node.id ? 0.95 : 0.75))
            .overlay(alignment: .topLeading) {
                if rect.width > 70 && rect.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name).font(.caption.bold()).lineLimit(1)
                        Text(node.size.formattedBytes).font(.caption2.monospacedDigit()).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }
            }
            .frame(width: max(0, rect.width - 3), height: max(0, rect.height - 3))
            .offset(x: rect.minX, y: rect.minY)
            .onHover { inside in if inside { hovered = node } else if hovered?.id == node.id { hovered = nil } }
            .onTapGesture { open(node) }
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                Button("Move to Trash…", role: .destructive) { trash(node) }
            }
    }

    static func color(for node: SpaceNode) -> Color {
        if !node.isDirectory {
            switch node.url.pathExtension.lowercased() {
            case "mov", "mp4", "mkv", "m4v": return .purple
            case "dmg", "iso", "zip", "pkg", "xip", "gz", "tar": return .orange
            case "app": return .blue
            default: return .gray
            }
        }
        let palette: [Color] = [.indigo, .teal, .blue, .cyan, .mint, .green]
        return palette[abs(node.name.hashValue) % palette.count]
    }
}

enum TreemapLayout {
    /// Squarified treemap (Bruls, Huizing, van Wijk). `sizes` must be sorted descending.
    static func squarify(sizes: [Double], in rect: CGRect) -> [CGRect] {
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return sizes.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        var areas = sizes.map { $0 * scale }
        var result: [CGRect] = []
        var remaining = rect

        while !areas.isEmpty {
            let side = Double(min(remaining.width, remaining.height))
            var row: [Double] = []
            var best = Double.infinity
            while let next = areas.first {
                let candidate = row + [next]
                let ratio = worst(candidate, side: side)
                if row.isEmpty || ratio <= best { row = candidate; best = ratio; areas.removeFirst() } else { break }
            }
            let rowArea = row.reduce(0, +)
            if remaining.width >= remaining.height {
                let w = CGFloat(rowArea / Double(remaining.height))
                var y = remaining.minY
                for a in row {
                    let h = CGFloat(a) / w
                    result.append(CGRect(x: remaining.minX, y: y, width: w, height: h))
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: remaining.width - w, height: remaining.height)
            } else {
                let h = CGFloat(rowArea / Double(remaining.width))
                var x = remaining.minX
                for a in row {
                    let w = CGFloat(a) / h
                    result.append(CGRect(x: x, y: remaining.minY, width: w, height: h))
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: remaining.height - h)
            }
        }
        return result
    }

    private static func worst(_ row: [Double], side: Double) -> Double {
        let s = row.reduce(0, +)
        guard let maxA = row.max(), let minA = row.min(), s > 0, minA > 0 else { return .infinity }
        let s2 = s * s, w2 = side * side
        return max(w2 * maxA / s2, s2 / (w2 * minA))
    }
}
