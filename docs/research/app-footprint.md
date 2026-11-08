# Finding an app's App Footprint (and Leftovers)

Research for [#3](https://github.com/devendra-nationalwala/glasswipe/issues/3): what reliably identifies the files outside an app's bundle that belong to it, how Pearcleaner and AppCleaner match them, and where they get it wrong.

Date: 2026-11-07. Validated on a test Mac by read-only inspection of `~/Library` and `/Library`. Nothing was modified.

Terms follow [GLOSSARY.md](../../GLOSSARY.md): **App Footprint**, **Leftovers**, **Uninstall**, **Startup Item**.

## Answer

Build the App Footprint from **identifiers read from the app's code signature and bundle**, not from its display name:

1. The **bundle ID** (`CFBundleIdentifier`) of the app and of every nested bundle: helpers, login items, app extensions, system extensions, XPC services.
2. The **Team ID** from the code signature.
3. The **app-group IDs** from the `com.apple.security.application-groups` entitlement.

Then look these up in a fixed set of locations whose naming Apple's frameworks control.

- **Exact bundle-ID matches** in system-controlled locations are high confidence and can be pre-selected. These are `Containers`, `Group Containers`, `Application Scripts`, `Preferences/<id>.plist`, `Saved Application State/<id>.savedState`, `HTTPStorages`, `WebKit`, and `Caches/<id>`.
- **Matches by app name** are low confidence. Examples are `Application Support/<Name>` and `Caches/<Name>`. Show them, but leave them unchecked.
- **Leave out "contains"-style substring matches on short names.** Most of the false positives below come from them.
- **Startup Items need separate sources:**
  - `/Library/LaunchAgents`, `/Library/LaunchDaemons` and `/Library/PrivilegedHelperTools`, matched on a bundle-ID or Team-ID prefix.
  - The Background Task Management database (`sfltool dumpbtm`).
  - `systemextensionsctl list`.
- **pkgutil receipts are a weak signal.** They only list the files the installer laid down, which is often just the `.app` itself.

**Leftovers** use the same rules in reverse. Any high-confidence item whose ID matches no installed bundle is a Leftover candidate.

- **Leave out** `com.apple.*` items and items whose IDs match any installed app's bundle ID, Team ID or group IDs.
- **Use the stored container metadata** when the container's folder name is not the ID.

## Signals, ranked

| Signal | How to get it | Where it names files | Confidence |
|---|---|---|---|
| Bundle ID, exact | `Info.plist` `CFBundleIdentifier`, for the app and every nested `.app`/`.appex`/`.systemextension`/`.xpc` | `~/Library/{Containers, Preferences/<id>.plist, Preferences/ByHost/<id>.*.plist, Caches, HTTPStorages, WebKit, Saved Application State/<id>.savedState, Application Scripts, Application Support/<id>, Logs/<id>}` | High |
| App-group IDs | entitlement `com.apple.security.application-groups`, either `group.<name>` or `<TEAMID>.<name>` | `~/Library/Group Containers/<group-id>`, `~/Library/Application Scripts/<group-id>` | High |
| Team ID | code signature (`kSecCodeInfoTeamIdentifier`) | prefix of group containers and Application Scripts entries (`BQR82RBBHL.*`); `systemextensionsctl` and BTM records | High as a filter, never on its own |
| Container metadata | `~/Library/Containers/*/.com.apple.containermanagerd.metadata.plist` → `MCMMetadataIdentifier` (undocumented) | containers whose folder name is not the bundle ID | High; needs Full Disk Access |
| BTM records | `sfltool dumpbtm`: Bundle Identifier, Team Identifier, URL, Parent Identifier | login items and agents registered via `SMAppService` / legacy APIs | High for Startup Items |
| System extensions | `systemextensionsctl list` (teamID, bundleID) | network, endpoint and driver extensions | High; the OS removes them when the app is deleted |
| Launchd plists | file name, plus the `Label` / `Program` / `AssociatedBundleIdentifiers` keys inside | `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools` | Medium–High |
| pkgutil receipts | `pkgutil --pkgs`, `--files <id>`, `--pkg-info <id>` | files the installer laid down (BOM) | Low coverage: postinstall-created files are missing |
| App name / executable name | `CFBundleName`, `CFBundleExecutable`, `.app` file name | `Application Support/<Name>`, `Caches/<Name>`, `Logs/<Name>`, `~/.<name>` dotfolders | Low; exact, case-insensitive only |
| Vendor / company token | middle part of the bundle ID, vendor folders | `/Library/Application Support/<Vendor>` | Very low; suggest only |

## What Apple documents

- **Library conventions.** The [File System Programming Guide – macOS Library Directory Details](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html) covers these folders:
  - *Application Support*: items go "in a subdirectory whose name matches the bundle identifier". This is a convention, and Electron apps break it, as shown below.
  - *Caches*: the same convention.
  - *Preferences*: managed by `NSUserDefaults`, so files are named `<bundleID>.plist`.
  - *Containers*: "home directories for any sandboxed apps".
  - *LaunchAgents* and *LaunchDaemons*.

  The guide does **not** cover Saved Application State, HTTPStorages, WebKit or Group Containers. That those folders are named by bundle ID is observed below, not documented.
- **Sandbox containers.** [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) says the container is created in `~/Library/Containers` on first launch. On macOS 14 and later it is tied to the app's code signature.
- **App groups.**
  - The [application-groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups) uses `group.<name>`, or on macOS `<team identifier>.<name>`.
  - Per [`containerURL(forSecurityApplicationGroupIdentifier:)`](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)), on macOS the folder is `~/Library/Group Containers/<group-id>`. The system creates it and "never removes it", so group containers are guaranteed Leftovers.
  - The same page says a URL is always returned, even for an invalid group, so check that the folder exists.
- **SMAppService** ([docs](https://developer.apple.com/documentation/servicemanagement/smappservice), macOS 13 and later). Agents, daemons and login items live **inside the bundle**, in `Contents/Library/{LaunchAgents,LaunchDaemons,LoginItems}`. Registering them leaves no plist in `/Library`; the record lives in Background Task Management.

  The [Apple Platform Deployment guide](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) documents `sfltool dumpbtm` for inspecting those records. It is unverified what happens to a BTM record once its app is deleted.
- **System extensions** ([Installing System Extensions and Drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers)): "The system automatically uninstalls any system extensions when the user deletes the corresponding app." Glasswipe should list them but not remove them.
- **Receipts** (`man 1 pkgutil`): the man page says "the files and directories where receipts are stored are subject to change. Always use pkgutil to query or modify them". So call `pkgutil`; don't parse `/var/db/receipts`. `--forget` removes only the receipt.

## How Pearcleaner does it

Source read at commit [`7724df7`](https://github.com/alienator88/Pearcleaner/tree/7724df7111bff82ae243301cf701992ef05ecf19). Paths below are relative to that tree.

- **Locations.** A hard-coded list in [`Logic/Locations.swift` L58–156](https://github.com/alienator88/Pearcleaner/blob/7724df7111bff82ae243301cf701992ef05ecf19/Pearcleaner/Logic/Locations.swift#L58-L156) covers:
  - all the standard `~/Library` and `/Library` subfolders, plus `~`, `~/.config`, `~/Documents` and `~/Desktop`
  - `/Users/Shared`, `/private/var/db/receipts`, `/private/tmp` and `/usr/local/*`
  - the per-user Darwin cache and temp folders
  - every subfolder of `~/Library/Application Support`.

  Each location is scanned to depth 1. `~/Library` and `/Library` go to depth 2, skipping ~130 Apple folders, and on a hit they select the vendor's parent folder.
- **Identifiers.** All are built in [`AppPathsFetch.swift` L77–131](https://github.com/alienator88/Pearcleaner/blob/7724df7111bff82ae243301cf701992ef05ecf19/Pearcleaner/Logic/AppPathsFetch.swift#L77-L131):
  - the bundle ID, and the last two bundle-ID parts joined together
  - the app name, a letters-only version of it, and the `.app` file name
  - the name with trailing version digits removed
  - the company part of the bundle ID
  - the Team ID
  - a "base" bundle ID with a `helper`/`agent`/`daemon`/… suffix dropped
  - an "entitlements" list ([`AppInfoFetch.swift` L690–785](https://github.com/alienator88/Pearcleaner/blob/7724df7111bff82ae243301cf701992ef05ecf19/Pearcleaner/Logic/AppInfoFetch.swift#L690-L785)). It holds app groups, iCloud containers, the names of `Contents/MacOS` binaries with 5+ characters, and nested app names.
- **Normalization.** `pearFormat()` keeps alphanumerics only and lowercases ([`Utilities.swift` L703–721](https://github.com/alienator88/Pearcleaner/blob/7724df7111bff82ae243301cf701992ef05ecf19/Pearcleaner/Logic/Utilities.swift#L703-L721)).
- **Sensitivity levels** ([`AppPathsFetch.swift` L323–434](https://github.com/alienator88/Pearcleaner/blob/7724df7111bff82ae243301cf701992ef05ecf19/Pearcleaner/Logic/AppPathsFetch.swift#L323-L434)):
  - *Strict*, the default: bundle ID by **contains**, names by exact match.
  - *Enhanced*: names by contains.
  - *Deep*: adds the company name and Team ID by contains.
- **Extra sources.**
  - Container metadata, keeping containers where `MCMMetadataIdentifier == bundleID`.
  - `containerURL(forSecurityApplicationGroupIdentifier:)`, but called with the **bundle ID** rather than the group IDs.
  - A Spotlight `NSMetadataQuery` with a 5-second timeout and a 500-result cap.
  - A per-app keyword table, `conditions`, for Chrome, Firefox, VS Code, JetBrains and others ([`Conditions.swift` L45–202](https://github.com/alienator88/Pearcleaner/blob/7724df7111bff82ae243301cf701992ef05ecf19/Pearcleaner/Logic/Conditions.swift#L45-L202)).
- **Leftovers ("orphans").** [`ReversePathsFetch.swift` L207–278](https://github.com/alienator88/Pearcleaner/blob/7724df7111bff82ae243301cf701992ef05ecf19/Pearcleaner/Logic/ReversePathsFetch.swift#L207-L278) lists the top level of each location. It drops:
  - anything whose normalized path **contains** an identifier of any installed app
  - anything matching about 200 `skipReverse` substrings (`apple`, `google`, `microsoft`, `sparkle`, …).

  It does not scan `Group Containers`. It is pure name subtraction: no receipts, no BTM, no Spotlight.
- **Not used for discovery:** receipt BOMs, BTM/`sfltool` and `systemextensionsctl`. `/Library/SystemExtensions` is explicitly skipped.

### Pearcleaner false positives, from its issue tracker

Each cause below is inferred from the code above; the issues only report symptoms.

| Issue | What happened | Cause |
|---|---|---|
| [#587](https://github.com/alienator88/Pearcleaner/issues/587) | Uninstalling OpenSCAD deleted `~/Documents/OpenSCAD`, which held user files | `~/Documents` is scanned, and an exact name match succeeds even in Strict mode |
| [#571](https://github.com/alienator88/Pearcleaner/issues/571) | A user folder "chrome (film simulation)" was deleted with Chrome | the Chrome `conditions` keyword is matched with contains |
| [#506](https://github.com/alienator88/Pearcleaner/issues/506) | Uninstalling Firefox Nightly deleted the shared Firefox profiles | the `firefox`/`mozilla` keywords also match the stable browser's data |
| [#393](https://github.com/alienator88/Pearcleaner/issues/393) | Firefox removal hit Thunderbird files; removing one Office app hit the others' files | shared vendor and name tokens |
| [#494](https://github.com/alienator88/Pearcleaner/issues/494) | Removing Chrome broke iCloud Passwords in Brave | a shared NativeMessagingHosts file; now on a skip list |
| [#616](https://github.com/alienator88/Pearcleaner/issues/616) | Uninstalling Logic Pro trashed a `com.apple.quicklook.ThumbnailsAgent` container | a bundle-ID contains match with no `com.apple` guard |
| [#617](https://github.com/alienator88/Pearcleaner/issues/617), [#143](https://github.com/alienator88/Pearcleaner/issues/143), [#538](https://github.com/alienator88/Pearcleaner/issues/538) | Orphan cleanup flagged Shortcuts' `group.is.workflow.*` items, wiped Zen Browser data, and "breaks apps" | name-only subtraction misses apps whose IDs don't appear in the path |

## How AppCleaner does it

[AppCleaner](https://freemacsoft.net/appcleaner/), version 3.7, is **closed source**. Its site only says it "finds all these small files and safely deletes them" when you drop an app on it. It documents no locations and no matching algorithm, so its behaviour is unverified and it is not a usable reference.

## Validation

The heuristics were checked read-only against several kinds of installed apps: sandboxed Mac App Store apps, direct-download apps (including Electron apps) and a pkg-installed app with a system extension.

- **Simple case:** for a sandboxed app, the exact bundle ID finds `Containers/<id>` and `Application Scripts/<id>`.
- **Entitlements matter:** Team-ID-prefixed group containers (`<TEAMID>.<name>`) often don't contain the bundle ID at all, so only the app-group entitlement finds them.
- **Electron apps** can keep preferences under a framework ID (`com.electron.<name>.plist`) and support files under a lowercase app name, neither of which matches the bundle ID.
- **pkg installs:** the receipt can list only the `.app`, not the LaunchAgent or system extension the installer created.
- **Substring matching is dangerous:** a contains match on a short app name such as "Code" hits many unrelated apps.
- **Privacy protection:** reading another app's `Group Containers/<id>` or a container's metadata fails with `Operation not permitted` unless the scanner has Full Disk Access.

## Implications for Glasswipe

1. **Gather identifiers first.** Walk the bundle and collect the bundle IDs of the app and every nested bundle under `Contents/{Library,PlugIns,XPCServices,Helpers,Frameworks}`. Add the Team ID and the app-group entitlements, and the `CFBundleName`, `CFBundleExecutable` and `.app` file name as **low-confidence** name keys. Use the Security framework (`SecStaticCode`); don't shell out.
2. **Two confidence tiers.**
   - *Certain*: an exact match on an ID, or `<id>.<known suffix>`, in a system-named location. Pre-selected.
   - *Likely*: an exact case-insensitive name match in `Application Support`, `Caches` and `Logs`, plus `/Library` vendor folders whose ID prefix matches. Shown but not selected.
   - Never use substring matching, never scan `~/Documents` or `~/Desktop`, and never descend into user-content folders.
3. **Startup Items.** Match `/Library/Launch{Agents,Daemons}` and `PrivilegedHelperTools` by file name or `Label` with a bundle-ID or Team-ID prefix, and read `AssociatedBundleIdentifiers`. Cross-check BTM records for in-bundle `SMAppService` items: those go away with the bundle, but their BTM records may linger. List system extensions as "removed by macOS".
4. **Receipts.** Use `pkgutil --pkgs` with a bundle-ID prefix and offer `pkgutil --forget`. Treat `--files` only as a hint for paths outside the bundle.
5. **Leftovers.** Take every *Certain*-tier item whose ID matches no installed bundle ID, group ID or Team ID. Exclude anything from Apple. Group containers must be included, since Apple never removes them on macOS, and Pearcleaner skips them. Find installed bundles via LaunchServices or Spotlight (`kMDItemCFBundleIdentifier`) across all volumes, not just `/Applications`.
6. **Permissions.** Glasswipe will need Full Disk Access to size containers and group containers and to read container metadata. Removing items from `/Library` needs admin rights or a privileged helper.

## Open questions

- Is there a supported way to map a UUID-named container to its owner without the undocumented `MCMMetadataIdentifier`, for example with `codesign` or `containermanagerd` tooling?
- What happens to BTM records when an app with an `SMAppService` login item is deleted? Do they linger, and can a non-privileged app remove them (`sfltool resetbtm` resets everything)?
- How should Glasswipe handle Electron apps whose preferences use a framework ID (`com.electron.*`, `com.github.Electron`)? An allowlist per app, or matching the `ElectronAppId` / `productName` from the bundle?
- What permission UX does a non-notarized app need (Full Disk Access, App Data, admin rights for `/Library`)? This is a candidate for its own ticket.
