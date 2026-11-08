# Glasswipe

A native macOS cleaner, in the spirit of CleanMyMac: clears Junk, frees memory, and uninstalls apps along with everything they leave behind. Built with SwiftUI and Liquid Glass for macOS 26 and later.

> **Status: planning.** There is no app to build yet. The v1 spec is being worked out in the open on the [planning map](https://github.com/devendra-nationalwala/glasswipe/issues/1). This README is updated as decisions land.

## Planned v1 features

| Feature | What it does |
|---|---|
| **Storage Cleaner** | Finds and removes Junk: caches, logs, temp files, Trash, and Developer Junk (Xcode, `node_modules`, Homebrew/npm/pip/uv/Docker caches) |
| **Memory Cleaner** | Shows real memory pressure and frees RAM by quitting or relaunching the processes that hold it, with your approval |
| **Uninstaller** | Removes an app together with its App Footprint: preferences, support files, containers, launch agents, receipts |
| **Leftovers** | Finds files left behind by apps you already deleted |
| **Space Lens** | Visual map of what is using your disk |
| **Large & Old Files** | Finds big or long-untouched files |
| **Startup Items** | Lists and toggles login items, launch agents and daemons |
| **Menu bar monitor** | Disk, memory, CPU and battery at a glance |

Out of scope: Mac App Store distribution (its sandbox blocks the core features), malware scanning.

Terms like Junk, Scan, Cleanup, App Footprint and Leftovers have precise meanings; see [`GLOSSARY.md`](GLOSSARY.md).

## Requirements

**To run:** macOS 26 (Tahoe) or later, Apple Silicon.

**To build:**

- macOS 26 or later
- Full **Xcode** (not just the Command Line Tools); developed with Xcode 27.2, macOS 27.2 SDK, Swift 6.4
- An **Apple Development signing identity**; a free Apple account is enough

### Installing Xcode from the command line

You must already be signed in to the App Store app.

```bash
brew install mas
sudo sh -c 'mas get 497799835 && xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -license accept && xcodebuild -runFirstLaunch'
xcodebuild -version   # should print Xcode 27.x or later
```

Only the macOS platform is needed; skip iOS and visionOS runtimes.

## Permissions

Glasswipe is a personal, non-notarized build, so macOS asks you to grant access yourself:

- **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access) is needed to scan protected locations such as Trash, Safari, Mail and other apps' containers. Most Junk in your home folder does not need it.
- **Sign every build with the same identity.** macOS ties Full Disk Access to the app's code signature. Ad-hoc signed builds lose the grant on every rebuild; an Apple Development identity keeps it.
- **Admin password** is asked only for the few system locations that need it (for example `/Library/Caches`).

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
AGENTS.md            instructions for coding agents working in this repo
GLOSSARY.md          the project's domain language
docs/agents/         how agents use the issue tracker and domain docs
docs/adr/            architecture decision records (created as decisions land)
```

Research findings are on the `research/*` branches.

## Contributing

- Read [`GLOSSARY.md`](GLOSSARY.md) and use its terms in code, issues and commits.
- Check the [planning map](https://github.com/devendra-nationalwala/glasswipe/issues/1) before proposing a feature; it may already be decided or ruled out of scope.
- Commits: plain, descriptive messages; no co-author trailers or tool attribution lines.

## Forking

Everything works the same in a fork. Replace `devendra-nationalwala/glasswipe` in `AGENTS.md`, `docs/agents/issue-tracker.md` and the links above with your own repo, and recreate the `wayfinder:*` labels if you want to use the planning workflow.

## License

[MIT](LICENSE)
