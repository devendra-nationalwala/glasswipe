import AppKit
import SwiftUI

/// Links to the project on GitHub. Forks change `repository` here.
enum Project {
    static let repository = URL(string: "https://github.com/devendra-nationalwala/glasswipe")!
    static let issues = repository.appendingPathComponent("issues/new")
    static let releases = repository.appendingPathComponent("releases")
    static let author = "Devendra Nationalwala"
    static let authorProfile = URL(string: "https://github.com/devendra-nationalwala")!
    /// Stripe Payment Link where the donor chooses the amount. Forks replace or remove it.
    static let donate = URL(string: "https://donate.stripe.com/4gMdRa8GPapX8oSgoO8og01")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// The standard About panel, with a credits line for the author and links.
    @MainActor static func showAbout() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        let credits = NSMutableAttributedString(string: "Built by \(author)\n", attributes: base)
        var link = base
        link[.link] = repository
        credits.append(NSAttributedString(string: "github.com/devendra-nationalwala/glasswipe", attributes: link))
        credits.append(NSAttributedString(string: "\nFree and open source under the MIT License.", attributes: base))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    /// Opens the repository page, where the Star button is. Starring needs the user's GitHub sign-in in the browser.
    @MainActor static func star() { NSWorkspace.shared.open(repository) }

    /// Opens the donation page in the browser. Stripe handles the payment; the app never sees it.
    @MainActor static func buyCoffee() { NSWorkspace.shared.open(donate) }
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

/// "Buy Me a Coffee" button used in the sidebar, menu bar and Settings.
struct CoffeeButton: View {
    var compact = false

    var body: some View {
        Button(action: Project.buyCoffee) {
            if compact {
                Image(systemName: "cup.and.saucer")
            } else {
                Label("Buy Me a Coffee", systemImage: "cup.and.saucer")
            }
        }
        .help("Like Glasswipe? Buy the developer a coffee")
    }
}
