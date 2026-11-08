import AppKit
import SwiftUI

/// `Glasswipe --snapshot <folder>` scans, visits every module and saves a PNG of the window for each,
/// then quits. Used to produce README screenshots; the app captures only its own window.
@MainActor
enum Snapshot {
    static var folder: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func run(_ model: AppModel, into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Cached window drawings skip the window background, so dark-mode text would vanish on white.
        NSApp.appearance = NSAppearance(named: .aqua)
        try? await Task.sleep(for: .seconds(1))
        async let a: Void = model.storage.scan()
        async let c: Void = model.leftovers.scan()
        _ = await (a, c)
        // Developer Junk can take minutes on machines with huge tool caches; only include it when asked.
        if CommandLine.arguments.contains("--with-developer") { await model.developer.scan() }
        for module in Module.allCases {
            model.selection = module
            try? await Task.sleep(for: .seconds(module == .uninstaller || module == .spaceLens ? 6 : 2.5))
            capture(to: folder.appendingPathComponent("\(module.rawValue).png"))
        }
        NSApp.terminate(nil)
    }

    static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.title == "Glasswipe" && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("snapshot: no window among \(NSApp.windows.map { "\($0.title)|\($0.isVisible)" })\n".utf8))
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
