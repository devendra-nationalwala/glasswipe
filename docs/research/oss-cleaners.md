# What can Glasswipe borrow from existing open-source Mac cleaners?

Research for issue #7. Checked on 2026-11-07 against the projects' own repositories (GitHub API metadata, LICENSE files, READMEs and source) and, for GrandPerspective, its SourceForge site. Star counts and last-push dates come from the GitHub API on that day.

## Answer in brief

- **Borrow ideas freely, and copy code only from permissive projects.** Glasswipe is now MIT-licensed (`LICENSE` on `main`). The useful code (Stats for the menu bar monitor, Mac Sai for a full Swift cleaner) is MIT or BSD-3, so Glasswipe can reuse it by keeping the copyright notice.
- **Treat Pearcleaner and Mole as references only, not code to copy.** Pearcleaner uses Apache-2.0 plus the Commons Clause, which is source-available, not open source. Mole is GPL-3.0. Copying from either would force its terms onto Glasswipe. Read them to learn which locations to scan, then write Glasswipe's own rules and logic.
- **The most reusable pieces are patterns and data:** where an App Footprint can live, how to match files to an app, which caches are safe to clean, which paths must never be touched, and how to show a Scan for review before Cleanup.
- **No project offers a real Memory Cleaner to copy.** Mole removed its swap cleanup as unsafe. Stats only reads memory figures. That suggests Glasswipe's Memory Cleaner should focus on showing memory use and acting on processes, not on "freeing RAM" tricks.

## Projects surveyed

| Project | Covers (in Glasswipe's terms) | Language | Licence | Stars | Last push | Status |
|---|---|---|---|---|---|---|
| [alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner) | Uninstall, Leftovers ("orphaned files"), dev environments, Homebrew, PKG receipts | Swift / SwiftUI | Apache-2.0 + Commons Clause ([LICENSE.md](https://github.com/alienator88/Pearcleaner/blob/main/LICENSE.md)) | 15k | 2026-06-22 | **On hold**: the README says development stopped at the end of 2025 |
| [tw93/Mole](https://github.com/tw93/Mole) | Storage Cleaner, Developer Junk (`purge`), Uninstall, disk explorer (`analyze`), status dashboard, `optimize` | Bash + Go (CLI) | GPL-3.0; name and logo trademarked ([TRADEMARK.md](https://github.com/tw93/Mole/blob/main/TRADEMARK.md)) | 74k | 2026-11-08 | Very active. The native "Mole for Mac" app is a **separate proprietary product** |
| [exelban/stats](https://github.com/exelban/stats) | Menu bar monitor (CPU, GPU, RAM, disk, network, sensors, battery) | Swift | MIT | 43k | 2026-11-07 | Active, single maintainer, "not an open-contribution project" (README) |
| [iliyami/MacSai](https://github.com/iliyami/MacSai) | Almost all of Glasswipe's v1: System Junk, Project Junk, Space Lens, Large & Old Files, uninstaller, menu bar widget, plus malware and privacy tools | Swift 6 / SwiftUI, SwiftPM | BSD-3-Clause | 2.1k | 2026-11-07 | Active, but young (repo created 2026-05-27) |
| [gostonx/uninstally](https://github.com/gostonx/uninstally) | Uninstall + Leftovers, Finder extension | Swift / SwiftUI | MIT | 0.8k | 2026-07-13 | Active |
| [objective-see/KnockKnock](https://github.com/objective-see/KnockKnock) | Lists every persistence type (Startup Items and more) | Objective-C | GPL-3.0 | 0.8k | 2026-09-15 | Active |
| [objective-see/BlockBlock](https://github.com/objective-see/BlockBlock) | Watches persistence locations | Objective-C | GPL-3.0 | 0.9k | 2026-09-14 | Active |
| [vashpan/xcode-dev-cleaner](https://github.com/vashpan/xcode-dev-cleaner) | Xcode Developer Junk | Swift | GPL-3.0 | 1.6k | 2026-05-18 | Active |
| [GrandPerspective](https://grandperspectiv.sourceforge.net/) | Disk treemap (Space Lens) | Objective-C | GPLv2 ([SourceForge](https://sourceforge.net/projects/grandperspectiv/)) | n/a | 3.8.1, 2026-09-13 | Active. Also sold on the App Store for $2.99 |
| [yujitach/MenuMeters](https://github.com/yujitach/MenuMeters) | Menu bar monitor | Objective-C | GPL-2.0 | 3.1k | 2026-10-28 | Maintained fork |
| [gao-sun/eul](https://github.com/gao-sun/eul) | Menu bar monitor | SwiftUI | MIT | 10k | 2024-05-25 | Stale |
| [voidcosmos/npkill](https://github.com/voidcosmos/npkill), [tbillington/kondo](https://github.com/tbillington/kondo) | Developer Junk (node_modules, build products) | TS / Rust | MIT | 9.5k / 2.6k | 2026-11 / 2026-04 | Active |
| [bootandy/dust](https://github.com/bootandy/dust), [dundee/gdu](https://github.com/dundee/gdu), [Byron/dua-cli](https://github.com/Byron/dua-cli) | Disk usage scanners (CLI) | Rust / Go / Rust | Apache-2.0 / MIT / MIT | 12.6k / 6.2k / 6.4k | 2026-11 | Active |
| [Kevin-De-Koninck/Clean-Me](https://github.com/Kevin-De-Koninck/Clean-Me) | Storage Cleaner | Swift | MIT | 1.8k | 2021 | **Archived** |

A GitHub search for "mac cleaner" also turns up many small, new SwiftUI cleaners (OpenClean GPL-3.0, spare MIT, tidymint MIT, Mole-GUI GPL-3.0 and others). None has the track record to rely on. They show that "trash-first, explain every file" is now the expected safety bar.

## What each project offers Glasswipe

### Pearcleaner: the best reference for App Footprint discovery (read only)

- **Where to look.** [`Locations.swift`](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/Locations.swift) lists about 70 folders where an App Footprint can live. Besides the usual `~/Library/{Application Support,Caches,Containers,Group Containers,Preferences,Preferences/ByHost,Saved Application State,HTTPStorages,WebKit,LaunchAgents,Logs}`, it covers `/Library/{LaunchDaemons,PrivilegedHelperTools,Extensions}`, `/private/var/db/receipts`, the `darwin` cache and temp folders, `/usr/local/*`, `~/.config`, and third-party SDK caches such as Sparkle, Sentry, Crashlytics, Amplitude and Google Keystone.
- **How to match files to an app.** [`AppPathsFetch.swift`](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/AppPathsFetch.swift) matches normalised file names against the bundle ID, app name, the last two parts of the bundle ID, the company, the **team identifier** and the **entitlement / app-group IDs**. It adds Spotlight results, finds Containers by reading each container's own bundle-ID metadata, and has a user-adjustable **strict vs. enhanced sensitivity**, with per-app overrides and skip/allow rules (`Conditions.swift`).
- **Leftovers.** `ReversePathsFetch.swift` (the "Zombie" view) works backwards: it walks the Library folders and flags anything that matches no installed app.
- **Architecture to note.** It uses an SMAppService privileged helper for system folders, needs Full Disk Access, and has a small `Sentinel` launch agent (about 2 MB) that watches `~/.Trash` and offers cleanup when an app is trashed. It also relies on **private frameworks** (`PackageKit` `PK*` headers for receipts, `CommerceKit` / `StoreFoundation` for its App Store updater).
- **Licence.** The Commons Clause forbids anyone from selling the software or "a product or service whose value derives … substantially" from it, and the notice must travel with any copy. The README says this "prohibits any form of monetization" of modified versions. A free personal app would not break that, but copied code would carry a non-open-source condition into Glasswipe. Don't copy; re-implement from the ideas.

### Mole: the best reference for Junk rules and safety policy (read only)

- **Junk catalogue.** [`lib/clean/`](https://github.com/tw93/Mole/tree/main/lib/clean) holds the most complete open list of Junk locations: `user.sh`, `system.sh`, `caches.sh`, `app_caches.sh`, `brew.sh`, and `dev.sh` (about 270 KB of Developer Junk handlers for npm, pnpm, bun, uv, conda, Go, Rust, Gradle, mise, Nix, Docker / OrbStack, Xcode documentation, CoreSimulator and more). `project.sh` / `purge` finds build products inside project folders.
- **Developer Junk patterns worth copying as ideas:**
  1. Prefer the tool's own clean command (`go clean`, `bun pm cache rm`, `docker … prune`, pnpm store prune) over deleting folders.
  2. Check whether the tool is running before cleaning (`gradle_daemon_running`, `rust_build_process_state`, `_coresimulator_booted_device_state`).
  3. Resolve the real physical path before deleting, and refuse unsafe roots (`is_safe_pnpm_store_path`, `guarded_dev_cache_root_physical_path`).
- **Protection list.** [`lib/core/app_protection_data.sh`](https://github.com/tw93/Mole/blob/main/lib/core/app_protection_data.sh) is a data-only list of system bundle IDs that must never be uninstalled. It deliberately avoids a `com.apple.*` wildcard so user-installed Apple apps such as Xcode stay removable.
- **Safety model** ([README §Safety](https://github.com/tw93/Mole#safety), [SECURITY_AUDIT.md](https://github.com/tw93/Mole/blob/main/SECURITY_AUDIT.md)):
  - every command has a `--dry-run` preview;
  - a whitelist protects chosen caches, and **if the whitelist can't be read, cleanup stops**;
  - uninstall sends files to the Trash by default;
  - an uninstall **keeps personal data (settings, plugins) unless the user opts in** (`--with-data`), and keeps shared data still used by another installed copy;
  - a `history` log records every run;
  - "when Mole cannot prove an item is safe to change, it skips or refuses it."
- **Disk explorer and status.** `cmd/analyze` (Go) marks each scan result `complete` / `partial` / `unavailable`, so a zero size is never mistaken for an empty folder. It caches results and offers JSON output. `cmd/status` is a read-only health dashboard.
- **Memory.** `lib/optimize/tasks.sh` notes: "Removed: opt_swap_cleanup – Direct virtual memory operations pose system crash risk."
- **Licence and trademark.** GPL-3.0 code means copying any of it makes Glasswipe GPL-3.0. TRADEMARK.md separately asks forks not to use the Mole name or logo.

### Stats: code that can be reused for the menu bar monitor (MIT)

- One module per metric (`Modules/{CPU,GPU,RAM,Disk,Net,Sensors,Battery,…}`), each with a `readers.swift` that does the sampling and separate widget, popup and settings views, plus a shared `Kit` of widgets.
- The RAM reader ([`Modules/RAM/readers.swift`](https://github.com/exelban/stats/blob/master/Modules/RAM/readers.swift)) uses only public calls: `host_statistics64(HOST_VM_INFO64)`, `sysctlbyname("kern.memorystatus_vm_pressure_level")` (2 = warning, 4 = critical), `kern.memorystatus_level`, and `vm.swapusage`. This is exactly what Glasswipe's monitor and Memory Cleaner need, and the MIT licence allows copying it with attribution.
- Lessons from the README:
  - each module has a power cost, so let users turn modules off;
  - **macOS 26 adds a System Settings → Menu Bar permission** that apps must be allowed in;
  - fan control and SMC sensor keys are fragile on each new Apple chip (fan control is "legacy" and needs a privileged SMC helper);
  - widget updates through `chronod` are off by default because of system load.

### Mac Sai: closest to Glasswipe in scope, and reusable (BSD-3)

- A Swift 6 SwiftPM layout that is worth copying: **`MacCleanKit`**, a pure library with no FileManager or NSWorkspace calls, holds the policy and rules and is fully unit-tested (about 80 test files). `MacClean` is the app and `MacCleanMenu` is a separate menu bar helper.
- **Junk categories are pure data** ([`SimpleCategories.swift`](https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/Categories/SimpleCategories.swift)). Each `JunkCategory` declares `[ScanTarget]` entries (path, recursive, file extensions, exclude patterns, excluded paths), and a separate `TargetedScanner` does the reading. This matches Glasswipe's Scan / Cleanup split.
- **`SafetyGuard`** ([source](https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/SafetyGuard.swift)) checks every deletion batch: a cap on files per operation, rejection of empty or NUL paths, protected prefixes (`/System`, `/usr`, `/bin`…), checks after resolving symlinks, user-excluded folders, and a guard against a symlink being swapped between check and delete. It is BSD-3, so the code can be adapted with attribution.
- Its module names already include "Space Lens" and "Large & Old Files", the same names Glasswipe plans to use (those names come from CleanMyMac). Caveat: the project is only about 5 months old.

### Others

- **KnockKnock** (GPL-3.0) is the reference list of persistence types, and so of what a Startup Items manager could show: `Plugins/{LaunchItems,LoginItems,BTM,Kexts,Extensions,Cronjobs,LogInOutHooks,PeriodicScripts,AuthorizationPlugins,…}`. Its Background Task Management (BTM) reader ships as a prebuilt `libDumpBTM.a`. Even objective-see doesn't use a public API for this.
- **uninstally** (MIT) has models that may be worth a look for presenting Uninstall: `SafetyScore` / `SafetyFactor`, `FileExplanationEngine` (explains why each file is listed), `InstallationSourceDetector` (App Store, Homebrew or direct download) and a simulation (dry-run) result.
- **GrandPerspective** (GPLv2, Objective-C) is the long-running open-source treemap. Use it as a UX reference only: GPLv2-only code can't even be combined with Apache-2.0 code.
- **dust / gdu / dua** (permissive) show how to scan disks fast with parallel directory walks. They are useful for algorithms, but not Swift.
- **npkill / kondo** (MIT) list the project types and build folders to detect for Developer Junk (for example `node_modules`, `target`, `.build`, `DerivedData`, `__pycache__`, `.gradle`).

## Licence constraints on reuse

This is not legal advice. It summarises the licence terms in each repository's LICENSE file.

| Source licence | Copying code into Glasswipe | Effect on Glasswipe's licence choice |
|---|---|---|
| MIT / BSD-3 (Stats, Mac Sai, uninstally, eul, npkill, kondo, gdu, dua) | Allowed. Keep the copyright and licence notice (e.g. in `THIRD_PARTY_NOTICES`) | None. Fine for an MIT Glasswipe |
| Apache-2.0 (dust) | Allowed. Keep the notice and NOTICE file, and mark changes | Fine for an MIT Glasswipe. Those files then carry Apache terms |
| GPL-3.0 (Mole CLI, KnockKnock, BlockBlock, DevCleaner) | Not for an MIT Glasswipe. Copying would force the whole app to GPL-3.0 | Reference only |
| GPL-2.0-only (GrandPerspective, MenuMeters) | Not for an MIT Glasswipe | Reference only |
| Apache-2.0 + Commons Clause (Pearcleaner) | Not for an MIT Glasswipe. The "no selling" condition and its notice would come along | Reference only. It would make Glasswipe not open source (as OSI defines it) |

Notes:

- **Facts versus code.** A path such as `~/Library/Caches` is a fact about macOS, not copyrighted expression. Re-deriving Glasswipe's own list of locations, using Mole and Pearcleaner as pointers, is the clean route. Copying their source files or data files wholesale is copying.
- **Trademarks are separate from licences.** Don't use the Mole or Pearcleaner names or logos. "Space Lens" and "Large & Old Files" are CleanMyMac's feature names. The glossary should decide whether Glasswipe keeps them.
- **What MIT means for Glasswipe.** Because Glasswipe is MIT, it can take code from the MIT, BSD and Apache-2.0 sources (keeping their notices). It must not copy code from any GPL project or from Pearcleaner. Those can only inform a clean re-implementation. (Had Glasswipe chosen GPL-3.0, Mole, KnockKnock and DevCleaner code would have been usable too, but GPLv2-only code and Pearcleaner would still have been off-limits.)

## Patterns that recur across projects (candidates for Glasswipe's design)

1. **Keep rules separate from the scanner.** Junk categories and protected paths live as data in a library you can test (Mac Sai's `MacCleanKit`, Mole's data-only `app_protection_data.sh`).
2. **Run every deletion through one safety guard**: a protected-prefix list, symlink resolution, a guard against paths changing between check and delete, a cap on batch size, and user exclusions. If the guard can't load its rules, refuse to run.
3. **Default to the Trash, keep a history and allow undo** (Mole's `history`, Pearcleaner's `UndoManager`, Mac Sai's "Clean History … Restore").
4. **Match App Footprints by several signals**: bundle ID, team ID, app-group / entitlement IDs, the bundle ID stored in Containers metadata, and Spotlight, with strict and broad sensitivity. Keep personal data unless the user opts in.
5. **Clean Developer Junk with the tool's own command first**, and skip a cache while its tool is running.
6. **Mark Scan results whose size couldn't be measured** (Mole's `complete` / `partial` / `unavailable`).
7. **Privileges:** Full Disk Access to read, an SMAppService privileged helper for writing to system folders, and a separate lightweight menu bar or agent process.

## Sources

- Repo metadata: `gh api repos/<owner>/<repo>` (licence SPDX ID, stars, `pushed_at`, `archived`), 2026-11-07.
- Pearcleaner: [README](https://github.com/alienator88/Pearcleaner/blob/main/README.md), [LICENSE.md](https://github.com/alienator88/Pearcleaner/blob/main/LICENSE.md), `Pearcleaner/Logic/{Locations,AppPathsFetch,ReversePathsFetch,Conditions}.swift`, `PearcleanerSentinel/`, `PearcleanerHelper/`.
- Mole: [README](https://github.com/tw93/Mole/blob/main/README.md), [LICENSE](https://github.com/tw93/Mole/blob/main/LICENSE), [TRADEMARK.md](https://github.com/tw93/Mole/blob/main/TRADEMARK.md), `lib/clean/dev.sh`, `lib/core/app_protection_data.sh`, `lib/optimize/tasks.sh`, `cmd/analyze/`, `cmd/status/`.
- Stats: [README](https://github.com/exelban/stats/blob/master/README.md), [LICENSE](https://github.com/exelban/stats/blob/master/LICENSE), `Modules/RAM/readers.swift`.
- Mac Sai: [README](https://github.com/iliyami/MacSai/blob/main/README.md), [LICENSE](https://github.com/iliyami/MacSai/blob/main/LICENSE), `Sources/MacCleanKit/SafetyGuard.swift`, `Sources/MacCleanKit/Categories/SimpleCategories.swift`.
- KnockKnock: repo tree (`Plugins/`, `Libraries/BTM/libDumpBTM.a`).
- uninstally: repo tree (`Uninstally/Models`, `Uninstally/Services`).
- GrandPerspective: [project site](https://grandperspectiv.sourceforge.net/), [SourceForge project page](https://sourceforge.net/projects/grandperspectiv/).
