# Glasswipe

A personal, open-source macOS utility that reclaims storage and memory on the Mac it runs on, and removes apps together with everything they left behind.

## Language

### Cleaning

**Storage Cleaner**:
The part of Glasswipe that finds and removes Junk to reclaim disk space.
_Avoid_: Disk cleaner, memory cleaner (when meaning disk)

**Memory Cleaner**:
The part of Glasswipe that reduces RAM use by acting on running processes and system memory.
_Avoid_: RAM booster, RAM optimizer

**Junk**:
Files that are safe to remove because the system or an app recreates them or no longer needs them: caches, logs, temp files, build products.
_Avoid_: Clutter, garbage

**Developer Junk**:
Junk produced by developer tooling, such as build products, dependency folders, package-manager caches and container images.

**Scan**:
A read-only pass that finds candidates for removal and measures them, without changing anything.

**Cleanup**:
The act of removing the candidates the user approved after a Scan.
_Avoid_: Purge (reserved for the macOS `purge` command)

### Safety

**Safety Gate**:
The single check every path passes before any removal; it refuses Protected Locations and refuses everything if its rules are unavailable.

**Protected Location**:
A path Glasswipe never removes, whatever a rule or the user asks: system folders, the user's top-level folders, whole app containers, sealed data such as `Docker.raw`.
_Avoid_: Blacklist

**Safe item**:
A Scan result its owner recreates on its own; it starts selected.

**Review item**:
A Scan result that cannot be recreated or is shared state; it is shown but starts unselected.
_Avoid_: Risky item, unsafe item

### Apps

**Uninstall**:
Removing an installed app together with its App Footprint.
_Avoid_: Delete app

**App Footprint**:
Every file outside an app's bundle that belongs to that app: preferences, support files, caches, containers, launch agents and receipts.
_Avoid_: Related files, associated files

**Leftovers**:
An App Footprint whose app is no longer installed.
_Avoid_: Orphans, remnants

**Startup Item**:
Anything that launches automatically at login or boot: login items, launch agents and launch daemons.
_Avoid_: Autostart, background item (unless meaning macOS's own term)
