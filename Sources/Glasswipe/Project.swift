import AppKit
import SwiftUI

/// Links to the project on GitHub. Forks change `repository` here.
enum Project {
    static let repository = URL(string: "https://github.com/devendra-nationalwala/glasswipe")!
    static let issues = repository.appendingPathComponent("issues/new")
    static let releases = repository.appendingPathComponent("releases")

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Opens the repository page, where the Star button is. Starring needs the user's GitHub sign-in in the browser.
    @MainActor static func star() { NSWorkspace.shared.open(repository) }
}

/// "Star on GitHub" button used in the sidebar, menu bar and Settings.
struct StarButton: View {
    var compact = false

    var body: some View {
        Button(action: Project.star) {
            if compact {
                Image(systemName: "star")
            } else {
                Label("Star on GitHub", systemImage: "star")
            }
        }
        .help("Like Glasswipe? Star it on GitHub")
    }
}
