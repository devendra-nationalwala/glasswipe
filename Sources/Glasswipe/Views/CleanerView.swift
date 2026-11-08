import GlasswipeCore
import SwiftUI

/// Scan → review → Cleanup screen used by Storage Cleaner, Developer Junk, Leftovers and Large & Old Files.
struct CleanerView: View {
    let module: Module
    let subtitle: String
    let explanation: String
    @Bindable var session: ScanSession
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(module: module, subtitle: subtitle)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            FullDiskAccessBanner().padding(.horizontal, 24)
            content
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await session.scan() } } label: { Label("Scan", systemImage: "arrow.clockwise") }
                    .disabled(isBusy)
                    .help("Scan again")
            }
        }
        .sheet(isPresented: $confirming) {
            CleanupConfirmation(items: session.selectedItems) { Task { await session.clean() } }
        }
    }

    private var isBusy: Bool {
        switch session.phase {
        case .scanning, .cleaning: true
        default: false
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .idle:
            ScanPrompt(module: module, explanation: explanation) { Task { await session.scan() } }
        case .scanning(let label, let fraction):
            ScanningView(label: label, fraction: fraction, stop: session.canStopEarly ? { session.stopScan() } : nil)
        case .cleaning(let fraction):
            ScanningView(label: "Cleaning up…", fraction: fraction)
        case .done(let freed, let failed):
            DoneBanner(freed: freed, failed: failed, results: session.lastResults) { Task { await session.scan() } }
        case .results:
            if session.items.isEmpty {
                ContentUnavailableView("Nothing to clean", systemImage: "checkmark.seal",
                                       description: Text(session.stoppedEarly
                                           ? "The Scan was stopped before it found anything. Click Scan to start again."
                                           : "Glasswipe found nothing here worth removing."))
            } else {
                ResultsList(session: session)
                    .overlay(alignment: .bottom) {
                        ActionBar(
                            title: "\(session.selectedSize.formattedBytes) selected",
                            detail: session.stillMeasuring ?? summary,
                            actionTitle: "Clean Up",
                            actionSymbol: "sparkles",
                            enabled: !session.selectedItems.isEmpty && session.stillMeasuring == nil
                        ) { confirming = true } leading: {
                            if session.isStoppable {
                                Button("Stop & Review", systemImage: "stop.fill") { session.stopScan() }
                                    .buttonStyle(.glass)
                                    .controlSize(.large)
                                    .help("Stop scanning and clean up what has been found so far")
                            } else if session.stillMeasuring != nil {
                                ProgressView().controlSize(.small).padding(.leading, 4)
                            }
                        }
                    }
            }
        }
    }

    private var summary: String {
        let counts = "\(session.selectedItems.count) of \(session.items.count) items · \(session.totalSize.formattedBytes) found"
        return session.stoppedEarly ? "Scan stopped early · \(counts)" : counts
    }
}
