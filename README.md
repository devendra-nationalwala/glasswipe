# Glasswipe

A native macOS cleaner, in the spirit of CleanMyMac: clears Junk, frees memory, and uninstalls apps along with everything they leave behind. Built with SwiftUI and Liquid Glass for macOS 26 and later.

> **Status: v1 in development.** Every v1 feature below is implemented and builds from the command line. Decisions are tracked on the [planning map](https://github.com/devendra-nationalwala/glasswipe/issues/1).

## Quick start

```bash
git clone https://github.com/devendra-nationalwala/glasswipe.git
cd glasswipe
scripts/create-signing-identity.sh   # once: keeps Full Disk Access across rebuilds
scripts/build-app.sh --install       # builds, signs and copies Glasswipe.app to /Applications
open /Applications/Glasswipe.app
```

Then grant **Full Disk Access** (the app shows a banner with a button that opens the right Settings pane).

## Features

| Feature | What it does |
|---|---|
| **Storage Cleaner** | Finds and removes Junk: caches, logs, temp files, Trash, and Developer Junk (Xcode, `node_modules`, Homebrew/npm/pip/uv/Docker caches) |
| **Memory Cleaner** | Shows real memory pressure and frees RAM by quitting or relaunching the processes that hold it, with your approval |
| **Uninstaller** | Removes an app together with its App Footprint: preferences, support files, containers, launch agents, receipts |
| **Leftovers** | Finds files left behind by apps you already deleted |
| **Space Lens** | Visual map of what is using your disk |
| **Large & Old Files** | Finds big or long-untouched files |
| **Startup Items** | Lists, enables/disables and removes launch agents and daemons; flags broken ones |
| **Menu bar monitor** | Disk, memory, CPU and battery at a glance |

Out of scope: Mac App Store distribution (its sandbox blocks the core features), malware scanning.

### How Glasswipe keeps your files safe

- **Nothing is removed without review.** Every module scans first, shows what it found, and asks before cleaning up.
- **Safe items are pre-selected; anything that can't be recreated is unticked.** Name-only matches in the Uninstaller and every Leftover are opt-in.
- **Recreatable Junk is deleted; everything else goes to the Trash**, so you can put it back.
- **Tools clean themselves.** Homebrew, npm, pip, uv, Docker and others are cleaned with their own commands, never by deleting their files.
- **One Safety Gate** checks every path before removal and refuses system folders, your top-level folders, whole app containers and `Docker.raw`. If its rules fail to load, nothing can be removed.
- **Caches of running apps are skipped.** Browser caches are offered only while the browser is closed.
- **Everything is logged** to `~/Library/Logs/Glasswipe/cleanup.jsonl` and shown in History.
- **No fake RAM boosting.** The Memory Cleaner frees memory by quitting apps you choose, and shows the real before/after.

Terms like Junk, Scan, Cleanup, App Footprint and Leftovers have precise meanings; see [`GLOSSARY.md`](GLOSSARY.md).

## Requirements

**To run:** macOS 26 (Tahoe) or later, Apple Silicon.

**To build:**

- macOS 26 or later
- Full **Xcode** (not just the Command Line Tools); developed with Xcode 27.2, macOS 27.2 SDK, Swift 6.4
- A **stable signing identity**: an Apple Development identity (free Apple account) or the self-signed one `scripts/create-signing-identity.sh` creates

### Installing Xcode from the command line

You must already be signed in to the App Store app.

```bash
brew install mas
sudo sh -c 'mas get 497799835 && xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -license accept && xcodebuild -runFirstLaunch'
xcodebuild -version   # should print Xcode 27.x or later
```

Only the macOS platform is needed; skip iOS and visionOS runtimes.

## Building and testing

| Command | What it does |
|---|---|
| `swift build` | Debug build of the core library and app |
| `swift test` | Runs the test suite; every test works in a throwaway temp folder, never on your files |
| `scripts/build-app.sh` | Release build, assembled and signed as `build/Glasswipe.app` |
| `scripts/build-app.sh --install` | Same, then copies it to `/Applications` |
| `open Package.swift` | Opens the package in Xcode for previews and debugging |
| `build/Glasswipe.app/Contents/MacOS/Glasswipe --snapshot <folder>` | Scans, saves a PNG of every screen into `<folder>`, then quits (for screenshots) |

The build script signs with, in order: `$GLASSWIPE_SIGN_IDENTITY`, your first Apple Development identity, "Glasswipe Local Signing", or ad hoc as a last resort.

## Permissions

Glasswipe is a personal, non-notarized build, so macOS asks you to grant access yourself:

- **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access) is needed to scan protected locations such as Trash, Safari, Mail and other apps' containers. Most Junk in your home folder does not need it.
- **Sign every build with the same identity.** macOS ties Full Disk Access to the app's code signature. Ad-hoc signed builds lose the grant on every rebuild; an Apple Development identity or the "Glasswipe Local Signing" identity keeps it.
- **Admin password** is asked once per Cleanup, only for the few system locations that need it (`/Library/Caches`, `/Library/Logs`, system launch daemons, apps owned by root).
- **Notifications** (optional): the menu bar monitor can alert you when memory pressure is critical.

## How this project is planned

Planning uses a **wayfinder map**: one GitHub issue labelled `wayfinder:map` that indexes every decision, with each open question as a child issue.

| Label | Meaning |
|---|---|
| `wayfinder:research` | A fact to look up; findings live on a `research/<topic>` branch that is never merged |
| `wayfinder:grilling` | A decision made through discussion |
| `wayfinder:prototype` | A rough artifact (UI or logic) built to react to |
| `wayfinder:task` | Setup work that unblocks a decision |

A ticket is ready when everything blocking it is closed. Decisions are summarised on the map and recorded in full on their ticket.

## Repository layout

```
Package.swift                         Swift package: GlasswipeCore library, Glasswipe app, tests
Sources/GlasswipeCore/                all scanning, matching and removal logic (no UI)
  Resources/junk-rules.json           where Junk lives and how to remove it — edit this to add rules
  Safety/SafetyGate.swift             the single check every removal passes through
  Cleanup/                            CleanupExecutor, removers, cleanup log
  Scan/ Apps/ Memory/ Startup/ Disk/  one folder per module
Sources/Glasswipe/                    SwiftUI app: window, menu bar, settings
Tests/GlasswipeCoreTests/             test suite (temp folders only)
scripts/                              build, signing identity and icon scripts
AGENTS.md                             instructions for coding agents working in this repo
GLOSSARY.md                           the project's domain language
docs/agents/                          how agents use the issue tracker and domain docs
docs/adr/                             architecture decision records
```

Research findings are on the `research/*` branches.

## Contributing

- Read [`GLOSSARY.md`](GLOSSARY.md) and use its terms in code, issues and commits.
- Check the [planning map](https://github.com/devendra-nationalwala/glasswipe/issues/1) before proposing a feature; it may already be decided or ruled out of scope.
- Run `swift test` before committing. New removal logic needs a test that proves it stays inside its temp folder.
- To add a Junk location, add a rule to `junk-rules.json`; the `noRuleTargetsAProtectedLocation` test checks it against the Safety Gate.
- Commits: plain, descriptive messages; no co-author trailers or tool attribution lines.

## Forking

Everything works the same in a fork. Replace `devendra-nationalwala/glasswipe` in `AGENTS.md`, `docs/agents/issue-tracker.md` and the links above with your own repo, and recreate the `wayfinder:*` labels if you want to use the planning workflow.

## License

[MIT](LICENSE)
