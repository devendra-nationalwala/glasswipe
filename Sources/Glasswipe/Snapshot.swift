import AppKit
import ScreenCaptureKit
import SwiftUI

/// `Glasswipe --snapshot=<folder> [--demo]` visits every module and saves a PNG of the window for each, then quits.
/// Used for README screenshots. It captures only Glasswipe's own window, which needs no Screen Recording permission.
@MainActor
enum Snapshot {
    static var folder: URL? {
        // One argument: AppKit treats a separate path argument as a document to open and then skips the main window.
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--snapshot=") }) else { return nil }
        return URL(fileURLWithPath: String(arg.dropFirst("--snapshot=".count)))
    }

    static func run(_ model: AppModel, into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1))
        NSApp.activate()
        for _ in 0..<3 {
            if let window = mainWindow {
                window.setFrameAutosaveName("")
                window.setFrame(NSRect(x: 80, y: 80, width: 1280, height: 820), display: true, animate: false)
                window.makeKeyAndOrderFront(nil)
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        if !Demo.isOn {
            async let a: Void = model.storage.scan()
            async let c: Void = model.leftovers.scan()
            _ = await (a, c)
            if CommandLine.arguments.contains("--with-developer") { await model.developer.scan() }
        }
        for module in Module.allCases {
            model.selection = module
            try? await Task.sleep(for: .seconds(module == .uninstaller ? 30 : module == .spaceLens ? 4 : 2))
            let target = folder.appendingPathComponent("\(module.rawValue).png")
            // ScreenCaptureKit can stall (for example while the display sleeps); fall back after 5 s.
            let finished = await withTaskGroup(of: Bool.self) { group in
                group.addTask { await capture(to: target); return true }
                group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            if !finished, let window = mainWindow { fallbackCapture(window, to: target) }
        }
        NSApp.terminate(nil)
    }

    static var mainWindow: NSWindow? { NSApp.windows.first { $0.title == "Glasswipe" && $0.contentView != nil } }

    static func capture(to url: URL) async {
        guard let window = mainWindow else { return }
        do {
            let content = try await SCShareableContent.currentProcess
            guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                return fallbackCapture(window, to: url)
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription); using cached drawing\n".utf8))
            fallbackCapture(window, to: url)
        }
    }

    /// Cached drawing: no Liquid Glass or window background, but needs nothing from ScreenCaptureKit.
    static func fallbackCapture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
