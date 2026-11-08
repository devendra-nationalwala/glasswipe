# Junk locations safe to clean on macOS 26/27

Research for the question "Which Junk locations are safe to clean on macOS 26/27?" (wayfinder research ticket).
It covers every location the Glasswipe Storage Cleaner and Developer Junk could target. Terms (Junk, Developer Junk, Scan, Cleanup) follow `GLOSSARY.md`.

## Answer

- **Safe (the owner recreates it):** the per-user cache roots (`~/Library/Caches/*`, `$(getconf DARWIN_USER_CACHE_DIR)`), user logs, and package-manager caches (Homebrew, npm, pip, uv, Yarn, pnpm, Bun, Go, Cargo, Gradle, CocoaPods). Also Xcode DerivedData, `node_modules`, and browser HTTP caches when the browser is closed.
- **Caution (the data cannot be recovered, or the location is shared state):** Trash, Xcode Archives, simulator devices, iOS device backups, Docker images and volumes, Time Machine local snapshots, `$TMPDIR`, and ML model caches (Hugging Face, Ollama, Whisper models).
- **Never:** anything under `/System`, the sealed system volume, `/private/var/vm` (swap and sleepimage), `/private/var/db/*` other than unified-log maintenance done through `log`, whole `~/Library/Containers/*` or `Group Containers/*` trees, `~/Library/Application Support/*` (that holds app state, not Junk), and the Docker `Docker.raw` file itself.
- **Permissions:** almost everything that pays off is in the user's home folder and needs neither admin rights nor Full Disk Access (FDA). FDA is needed for `~/.Trash` and for Safari or Mail data. Admin rights are needed for `/Library/Caches`, `/Library/Logs`, `/private/var/log` and system temp folders, which are usually small.
- **Prefer the owner's command over `rm`** wherever one exists: `brew cleanup`, `npm cache clean --force`, `pip cache purge`, `uv cache clean|prune`, `docker system prune`, `xcrun simctl delete unavailable`, `tmutil thinlocalsnapshots`, `log erase`. These keep each tool's index consistent and respect its locks.

## Typical sizes

On a developer's Mac the largest items are usually package-manager caches (uv, npm, pip), Docker's disk image, browser caches and `node_modules` folders, often several to tens of GB each, while classic Junk (logs, small app caches) is typically a few GB. Developer Junk can outweigh classic Junk several times over, so it deserves its own module.

## Catalogue

Columns:

- **Recreated?** Whether macOS or the owning app rebuilds the location on demand.
- **Risk:** safe / caution / never.
- **Access:** what Glasswipe needs to read and delete there. *none* means a normal unsandboxed user process. *FDA* means Full Disk Access. *admin* means root or an authorization prompt.

### System and user Junk

| Path pattern | Recreated? | Risk | Access | Notes |
|---|---|---|---|---|
| `~/Library/Caches/<bundle-id or name>/*` | Yes. Apple: caches are data the app "can re-create as needed" [A1] | safe | none (some subfolders are TCC-gated, see the Safari row) | Delete the *contents*, not the top-level folder, and skip apps that are running. Some apps keep state here against Apple's guidance, notably updater `*.ShipIt` folders that hold a pending update. Deleting them only means the update is downloaded again |
| `$(getconf DARWIN_USER_CACHE_DIR)` = `/var/folders/xx/…/C/` | Yes (system per-user cache) | safe or caution | none | Contains caches for system daemons and font and Metal shader caches, which rebuild slowly. Clear only while the processes using them are idle. Better left to a reboot |
| `$TMPDIR` = `/var/folders/xx/…/T/` | Apps create files here at will. macOS removes old files at boot and periodically (dirhelper, launchd) [A2] | caution | none | Running apps hold open files here. Delete only items older than N days that no process has open (check with `lsof +D`) |
| `/var/folders/xx/…/0/` and other users' folders | – | never | admin | Belong to other users or the system |
| `/private/tmp` (= `/tmp`) | Cleared at boot | caution | none for own files, admin for others | Sockets and lock files of running daemons live here. Use an age filter and skip sockets |
| `~/Library/Logs/*` | Yes, apps append | safe | none | `DiagnosticReports` holds crash reports. They are safe to delete but useful for debugging, so offer age-based removal |
| `/Library/Logs/*`, `/private/var/log/*` | Yes (daemons, newsyslog) | caution | admin | Small. newsyslog/aslmanager already rotate them [A3]. Low priority |
| `/private/var/db/diagnostics`, `/private/var/db/uuidtext` | Unified logging (logd) manages size and TTL | never by hand. Use `log erase` if anything | admin | `log erase [--all] [--ttl]` is the supported tool [M1]. Deleting files directly corrupts the log store |
| `/Library/Caches/*` | Mostly yes | caution | admin | Usually small. Not worth an admin prompt in a first version |
| `/System/Library/Caches`, `/System/**` | – | never | not possible: SIP and the signed system volume | Has the `sunlnk` flag. Read-only sealed volume [A4] |
| `/private/var/vm/*` (swapfiles, sleepimage) | Managed by the kernel | never | – | Deleting them can panic the machine or break hibernation |
| `/Library/Updates/*` | softwareupdate | never | admin | Staged OS updates |
| `~/.Trash/*` | No. The user deleted these deliberately | caution | **FDA**. Without it, enumeration fails [A5] | Without FDA, the alternative is asking Finder to empty the Trash (Apple Events, which needs Automation consent). Show the size and confirm, because emptying is irreversible. Per-volume trashes are at `/Volumes/*/.Trashes/<uid>` |
| Time Machine local snapshots | Taken by TM (hourly, kept 24 h). APFS purges them under disk pressure | caution | none for `tmutil thinlocalsnapshots /`. `deletelocalsnapshots` may need admin | Use `tmutil thinlocalsnapshots <mount> [bytes] [urgency]` [M2]. These are a big "hidden space" source in Finder |
| `~/Library/Containers/<id>/Data/Library/Caches/*` | Yes (the sandboxed app's own caches) | safe | none for most; TCC-gated for Apple apps (Safari, Mail) | Only the `Data/Library/Caches` subpath. **Never** the whole container (that is the app's home folder and its data) |
| `~/Library/Group Containers/*` | – | never | – | Shared app data. That is App Footprint, not Junk |
| Mail Downloads `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | Mail can download attachments again | safe or caution | FDA | Small in practice |
| `~/Library/Application Support/MobileSync/Backup/<UDID>` | **No**. These are device backups | caution | FDA on recent macOS | Path from Apple [A6]. List them per device with dates, delete only on explicit selection, and warn that an encrypted backup may be the only copy |

### Browser caches

Delete browser caches only while the browser is not running. If it is running, skip it or ask the user to quit.

| Path pattern | Risk | Access | Notes |
|---|---|---|---|
| `~/Library/Caches/Google/Chrome/*/Cache`, `Code Cache`, `GPUCache` (also Brave `BraveSoftware/…`, Edge `com.microsoft.edgemac`, Opera, Arc, Comet) | safe | none | Only the cache folders. **Never** `~/Library/Application Support/Google/Chrome/*` (profiles, cookies, history) |
| `~/Library/Caches/Firefox/Profiles/*/cache2` | safe | none | Profile data lives in `Application Support/Firefox`. Leave it alone |
| Safari: `~/Library/Caches/com.apple.Safari`, `~/Library/Containers/com.apple.Safari/Data/Library/Caches` | safe | **FDA** (TCC-protected) | WebKit data under `~/Library/Safari` is not cache. Leave it alone |

### Developer Junk

| Path pattern | Recreated? | Risk | Access | Supported command |
|---|---|---|---|---|
| `~/Library/Developer/Xcode/DerivedData/*` | Yes, on the next build | safe | none | Delete while Xcode is closed or the project is not building [X1] |
| `~/Library/Developer/Xcode/Archives/*` | **No**. Archives hold the dSYMs needed to symbolicate shipped builds | caution | none | List per app and version. Default to keeping them |
| `~/Library/Developer/Xcode/{iOS,watchOS,tvOS,macOS} DeviceSupport/*` | Yes, rebuilt when the device is next connected (slow) | safe | none | Offer "older than the newest N OS versions" |
| `~/Library/Developer/CoreSimulator/Devices/*` | Device data is lost. Runtimes stay | caution | none | `xcrun simctl delete unavailable` is safe [X2]. Deleting all devices loses app data inside the simulators |
| `~/Library/Developer/CoreSimulator/Caches/*` | Yes | safe | none | |
| Simulator runtimes (`/Library/Developer/CoreSimulator/Volumes`, `Images`) | Can be downloaded again (GBs) | caution | admin, or `xcrun simctl runtime delete` | Use simctl. Never `rm` mounted runtime volumes |
| `/Library/Developer/CommandLineTools` | – | never | – | Toolchain, not Junk |
| `**/node_modules` (in project folders) | Yes, via `npm/pnpm/yarn install` | safe (caution if the project has no lockfile, or for untracked local patches) | none | Find them by walking user-chosen roots (for example `~/repos`). Prune the walk at `node_modules`. Show the date last modified |
| `~/.npm/_cacache`, `~/.npm/_npx` | Yes | safe | none | `npm cache clean --force`. npm says this is rarely needed and suggests `npm cache verify` [P1] |
| `~/Library/Caches/Yarn`, `~/Library/Caches/pnpm` + `~/Library/pnpm/store` | Yes | safe (the pnpm store is hard-linked into projects; pruning is safe, deleting a linked store makes the next install re-download) | none | `yarn cache clean`, `pnpm store prune` |
| `~/.bun/install/cache` | Yes | safe | none | `bun pm cache rm` |
| `~/Library/Caches/pip` | Yes | safe | none | `pip cache purge` [P2] |
| `~/.cache/uv` | Yes. **But** `uv python install` interpreters and `uv tool` environments may live in uv-managed folders | safe for `uv cache clean`/`prune` | none | Use `uv cache prune` (unused entries only) or `uv cache clean` [P3]. Do not `rm` while uv is running |
| `~/Library/Caches/Homebrew` (`brew --cache`) | Yes | safe | none | `brew cleanup [--prune=all]` [P4]. `rm -rf "$(brew --cache)"` is the documented full wipe |
| Homebrew old versions in `/opt/homebrew/Cellar/*/<old>` | – | safe through `brew cleanup` only | none (prefix is user-owned on Apple Silicon) | Never touch the Cellar directly |
| `~/Library/Caches/go-build`, `~/go/pkg/mod` | Yes | safe | none (modcache is read-only; needs `chmod` or `go clean -modcache`) | `go clean -cache -modcache` |
| `~/.cargo/registry/{cache,src}`, `target/` in projects | Yes | safe | none | `cargo clean` per project |
| `~/.gradle/caches`, `~/.m2/repository` | Yes (downloaded again) | safe | none | Stop Gradle daemons first |
| `~/Library/Caches/CocoaPods`, `~/.cocoapods/repos` | Yes | safe | none | `pod cache clean --all` |
| `~/Library/Caches/ms-playwright`, `~/.cache/puppeteer`, `~/Library/Caches/Cypress` | Yes (browser binaries) | safe | none | Tests download them again on the next run |
| Docker images, containers, volumes, build cache (inside `Docker.raw`) | Images and build cache: yes (pulled or rebuilt). **Volumes: no** (databases) | caution | none, but Docker must be running | `docker system prune` (without `--volumes` by default) [P5]. Space is only returned to macOS after Docker Desktop compacts the disk |
| `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | – | never `rm` | – | Deleting it destroys every image, container and volume. Use Docker Desktop "Clean / Purge data" instead |
| ML model caches: `~/.cache/huggingface`, `~/.ollama/models`, app model folders (for example speech-model folders under `~/.cache`) | Can be downloaded again, but large and slow (GBs) | caution | none | Treat as "large downloads", not automatic Junk |

## Rules for Glasswipe's Scan and Cleanup

1. **Scan stays read-only.** Measure with `du`-style traversal (allocated size, not apparent size: a sparse image such as `Docker.raw` can report hundreds of GB apparent while using far less on disk). Don't follow symlinks, and stay on one volume.
2. **Delete contents, not roots.** Keep `~/Library/Caches/<id>` and similar folders; remove what is inside them. Some apps break if their cache root is missing.
3. **Skip anything held open or owned by a running app.** Check the running bundle IDs (NSWorkspace) for app caches and `lsof` for temp folders.
4. **Use the owner's command when one exists** (see the table above). Fall back to removing files only for plain cache folders.
5. **Caution items need explicit, per-item selection** and are never pre-checked. Never items are not shown as candidates at all.
6. **Move to Trash or delete for good?** Junk that the owner recreates can be deleted outright. Caution items could go to the Trash so the user can undo, but that does not free space until the Trash is emptied. This is a product decision; see the open questions.
7. **Prompt for FDA only when needed:** for Trash, Safari, Mail and iOS backups. Everything else works without it.

## Sources

Primary sources. [M] and [A2] were read from the local man pages. The web docs are the canonical owner pages; their URLs are listed but were not re-fetched in this pass.

- [A1] Apple, *File System Programming Guide*, "macOS Library Directory Details" / "Where You Should Put Your App's Files". Caches are for data the app can re-create. https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html. Also `FileManager.SearchPathDirectory.cachesDirectory`: https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory
- [A2] `dirhelper(8)` (local man page). launchd creates the per-user `/var/folders` special directories. `getconf DARWIN_USER_TEMP_DIR` / `DARWIN_USER_CACHE_DIR` (local) resolve to `…/T/` and `…/C/`.
- [A3] `newsyslog(8)`, `aslmanager(8)` (local man pages). These rotate and expire system logs.
- [A4] Apple Platform Security, "Signed system volume security" and "System Integrity Protection". https://support.apple.com/guide/security/signed-system-volume-security-secd698747c9/web. `csrutil status` shows whether SIP is enabled.
- [A5] Apple Platform Security, "Controlling app access to files in macOS" (TCC, Full Disk Access). https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web. Confirmed locally: `ls ~/.Trash`, `~/Library/Safari`, `~/Library/Mail` and `~/Library/Containers/com.apple.Safari` are denied without FDA.
- [A6] Apple Support, "Locate backups of your iPhone, iPad and iPod touch". The path is `~/Library/Application Support/MobileSync/Backup/`. https://support.apple.com/en-us/108809
- [M1] `log(1)` (local man page): `log erase [--all] [--ttl] [--uuidtext]`.
- [M2] `tmutil(8)` (local man page): `thinlocalsnapshots mount_point [purge_amount] [urgency]`, `deletelocalsnapshots`.
- [X1] Apple, Xcode Help, "Manage build files / DerivedData" (Settings > Locations). https://developer.apple.com/documentation/xcode
- [X2] `xcrun simctl help delete` (`delete unavailable`), `simctl runtime delete`.
- [P1] npm Docs, `npm cache`. https://docs.npmjs.com/cli/commands/npm-cache
- [P2] pip docs, `pip cache`. https://pip.pypa.io/en/stable/cli/pip_cache/ (local `pip3 cache --help` confirms `dir`, `purge`, `remove`)
- [P3] uv docs, "Caching", `uv cache clean`/`prune`. https://docs.astral.sh/uv/concepts/cache/
- [P4] `brew cleanup --help` (local): it removes downloads older than 120 days, and `--prune=all` / `rm -rf "$(brew --cache)"` wipe everything. `brew --cache` reports `~/Library/Caches/Homebrew`.
- [P5] Docker Docs, `docker system prune`. https://docs.docker.com/reference/cli/docker/system/prune/ and Docker Desktop for Mac disk usage: https://docs.docker.com/desktop/settings-and-maintenance/settings/
- Cross-check against open-source cleaner rule sets: Mole (https://github.com/tw93/Mole) and Pearcleaner (https://github.com/alienator88/Pearcleaner) target the same `~/Library/Caches`, Logs, DerivedData, simulator and package-manager locations.
