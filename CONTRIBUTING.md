# Contributing to Glasswipe

Thanks for helping. This page is for people who want to build Glasswipe from source or change it. If you only want to use the app, see the [README](README.md).

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon
- Full **Xcode** (not just the Command Line Tools); developed with Xcode 27.2, macOS 27.2 SDK, Swift 6.4
- A **stable signing identity**: an Apple Development identity (free Apple account) or the self-signed one `scripts/create-signing-identity.sh` creates. macOS ties Full Disk Access to the app's signature, so ad-hoc builds lose it on every rebuild.

### Installing Xcode from the command line

You must already be signed in to the App Store app.

```bash
brew install mas
sudo sh -c 'mas get 497799835 && xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -license accept && xcodebuild -runFirstLaunch'
xcodebuild -version   # should print Xcode 27.x or later
```

Only the macOS platform is needed; skip iOS and visionOS runtimes.

## Build from source

```bash
git clone https://github.com/devendra-nationalwala/glasswipe.git
cd glasswipe
scripts/create-signing-identity.sh   # once
scripts/build-app.sh --install       # builds, signs and copies Glasswipe.app to /Applications
```

## Commands

| Command | What it does |
|---|---|
| `swift build` | Debug build of the core library and app |
| `swift test` | Runs the test suite; every test works in a throwaway temp folder, never on your files |
| `scripts/build-app.sh` | Release build, assembled and signed as `build/Glasswipe.app` |
| `scripts/build-app.sh --install` | Same, then copies it to `/Applications` |
| `scripts/make-dmg.sh` | Builds `build/Glasswipe.dmg`, the drag-to-Applications installer |
| `scripts/release.sh <version>` | Tags, builds the DMG and publishes a GitHub Release (needs `gh` with push access) |
| `open Package.swift` | Opens the package in Xcode for previews and debugging |
| `Glasswipe --report <kind>` | Read-only dry run: prints what a Scan finds and exits. Kinds: `junk`, `developer`, `leftovers`, `large`, `apps`, `startup`, `memory`, `footprint <app name>` |
| `open -n build/Glasswipe.app [--env GLASSWIPE_DEMO_HIDE=a,b] --args --demo --snapshot=<folder>` | Saves a PNG of every screen into `<folder>`, then quits. `--demo` fills the screens with sample data and never removes anything; `GLASSWIPE_DEMO_HIDE` hides real apps whose names contain any of the given words. Used for the README screenshots |

The build script signs with, in order: `$GLASSWIPE_SIGN_IDENTITY`, your first Apple Development identity, "Glasswipe Local Signing", or ad hoc as a last resort.

## Repository layout

```
Package.swift                         Swift package: GlasswipeCore library, Glasswipe app, tests
Sources/GlasswipeCore/                all scanning, matching and removal logic (no UI)
  Resources/junk-rules.json           where Junk lives and how to remove it — edit this to add rules
  Safety/SafetyGate.swift             the single check every removal passes through
  Cleanup/                            CleanupExecutor, removers, cleanup log
  Scan/ Apps/ Memory/ Startup/ Disk/  one folder per module
Sources/Glasswipe/                    SwiftUI app: window, menu bar, settings, demo and snapshot modes
Tests/GlasswipeCoreTests/             test suite (temp folders only)
scripts/                              build, DMG, release, signing identity and icon scripts
docs/screenshots/                     README screenshots
docs/adr/                             architecture decision records
docs/agents/                          how coding agents use the issue tracker and domain docs
GLOSSARY.md                           the project's domain language
AGENTS.md                             instructions for coding agents working in this repo
```

## Ground rules

- Read [`GLOSSARY.md`](GLOSSARY.md) and use its terms in code, issues and commits.
- Run `swift test` before committing. New removal logic needs a test that proves it stays inside its temp folder.
- To add a Junk location, add a rule to `junk-rules.json`; the `noRuleTargetsAProtectedLocation` test checks it against the Safety Gate.
- Anything that removes files must go through `CleanupExecutor` and the Safety Gate.
- Keep the README user-facing; developer details belong here.
- Commits: plain, descriptive messages; no co-author trailers or tool attribution lines.

## How the project is planned

Planning uses a **wayfinder map**: one GitHub issue labelled `wayfinder:map` that indexes every decision, with each question as a child issue. The v1 map is [issue #1](https://github.com/devendra-nationalwala/glasswipe/issues/1).

| Label | Meaning |
|---|---|
| `wayfinder:research` | A fact to look up; findings live on a `research/<topic>` branch that is never merged |
| `wayfinder:grilling` | A decision made through discussion |
| `wayfinder:prototype` | A rough artifact (UI or logic) built to react to |
| `wayfinder:task` | Setup work that unblocks a decision |

## Forking

Everything works the same in a fork. Replace `devendra-nationalwala/glasswipe` and the author name in `Sources/Glasswipe/Project.swift` and `scripts/build-app.sh` (copyright line), `AGENTS.md`, `docs/agents/issue-tracker.md`, `scripts/release.sh`, `scripts/make-dmg.sh` and the README links with your own repo, and recreate the `wayfinder:*` labels if you want to use the planning workflow. Replace the donation link (`Project.donate` in `Project.swift`, `.github/FUNDING.yml`, the README and `scripts/release.sh`) with your own, or remove it.

By contributing you agree your contributions are released under the [MIT License](LICENSE) and that the [disclaimer](README.md#disclaimer) applies to them.
