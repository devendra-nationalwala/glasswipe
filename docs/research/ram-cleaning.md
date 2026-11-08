# What RAM cleaning actually works on macOS?

Research for issue #4. Target: Apple Silicon Macs on macOS 26/27 (16 KiB pages). Terms follow `GLOSSARY.md`: the **Memory Cleaner** is the part of Glasswipe that reduces RAM use; "purge" means only the macOS `purge` command.

## Answer

macOS decides **memory pressure** from one number: how many pages are *not* wired and *not* held by the compressor. Moving pages between "file cache", "inactive" and "free" does not change that number. So:

- **Works:** reducing **anonymous memory** (heap) that processes hold: quitting or relaunching heavy/leaking apps, closing browser tabs, restarting bloated per-user background agents. Pages the compressor holds (and swap) are freed; the pressure gauge moves.
- **Works, but limited and temporary:** asking apps to drop their own caches by raising a fake pressure notification (`memory_pressure -S`, root only). Apps rebuild those caches.
- **Placebo for pressure:** `purge`, "free up inactive memory", "clear the file cache", and any "RAM booster" that allocates and then frees a large block. These make the "Free" figure jump while pressure, swap and compressor stay the same, and they slow the Mac down afterwards because the file cache has to be read back from SSD.

The Memory Cleaner should therefore be built around **per-process footprint** (find what holds anonymous/compressed memory, then quit or relaunch it on approval), with the system **pressure level** as its headline gauge. Do not put a purge button in it.

## How macOS measures pressure (the key fact)

On macOS the compressor is always on, so the pressure state machine compares `AVAILABLE_NON_COMPRESSED_MEMORY` to thresholds derived from total memory:

```c
// osfmk/vm/vm_page.h
#define AVAILABLE_NON_COMPRESSED_MEMORY (vm_page_active_count + vm_page_inactive_count + vm_page_free_count + vm_page_speculative_count)
#define AVAILABLE_MEMORY                (AVAILABLE_NON_COMPRESSED_MEMORY + VM_PAGE_COMPRESSOR_COUNT)
// non-jetsam macOS:
#define VM_CHECK_MEMORYSTATUS memorystatus_update_available_page_count(AVAILABLE_NON_COMPRESSED_MEMORY)
```

```c
// osfmk/vm/vm_pageout.c, VM_PRESSURE_NORMAL_TO_WARNING (compressor active)
return (AVAILABLE_NON_COMPRESSED_MEMORY < VM_PAGE_COMPRESSOR_COMPACT_THRESHOLD) ? 1 : 0;
// VM_PRESSURE_WARNING_TO_CRITICAL
return vm_compressor_low_on_space() || (AVAILABLE_NON_COMPRESSED_MEMORY < ((12 * VM_PAGE_COMPRESSOR_SWAP_UNTHROTTLE_THRESHOLD) / 10)) ? 1 : 0;
```

`kern.memorystatus_level` is the same quantity as a percentage: `memorystatus_level = available_memory * 100 / total_pages` (`osfmk/vm/vm_pageout.c`, `vm_pressure_response`).

Sources: [xnu `osfmk/vm/vm_page.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_page.h), [`osfmk/vm/vm_pageout.c`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_pageout.c), [`osfmk/vm/vm_compressor_xnu.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_compressor_xnu.h) (threshold macros).

**Checked on a test Mac** (`vm_stat`, `sysctl`, read-only): the formula matched the kernel's own `kern.memorystatus_level` reading to within one percentage point.

What follows from it:

| Pages move… | Effect on the pressure input |
|---|---|
| file cache (inactive/active) → free | **none**, both sides of the move are counted |
| resident anonymous → free (app quits) | none right away, but those pages can no longer be compressed later |
| compressed → freed (app that was compressed quits) | **goes up** by the compressor pages released |
| wired → freed | **goes up** |
| swap released | relieves `vm_compressor_low_on_space()` and SSD wear |

So only freeing compressed, wired or swapped memory moves the gauge, and in practice that means making processes give up anonymous memory.

## Action-by-action verdict

### `purge`: placebo for pressure, and it costs performance

- `man purge`: "force disk cache to be purged (flushed and emptied)… to approximate initial boot conditions with a cold disk buffer cache for performance analysis. It does not affect anonymous memory that has been allocated through malloc, vm_allocate, etc."
- `/usr/sbin/purge` imports only `_vfs_purge` and `_perror` (`nm -u`). The syscall (`bsd/vfs/vfs_syscalls.c`):

  ```c
  if (!kauth_cred_issuser(kauth_cred_get())) { return EPERM; }
  vfs_iterate(0, vfs_purge_callback, NULL);   // ubc_msync(... UBC_PUSHALL | UBC_INVALIDATE) on every vnode
  if (vfs_purge_vm_pagers) { vm_purge_filebacked_pagers(); }  // apple_protect, shared_region, dyld pagers
  ```
- It needs **root**. It turns file cache into free pages, which leaves the pressure input unchanged (see the table). Every evicted file, including dyld shared-region pages and app binaries, then has to be read back from SSD. It is a benchmarking tool, not a cleaner.
- Source: [xnu `bsd/vfs/vfs_syscalls.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_syscalls.c), [`bsd/vm/vm_unix.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vm/vm_unix.c), `man 8 purge`.

### "Free inactive memory" / allocate-then-release boosters: placebo

Inactive pages are already counted as available (they are in `AVAILABLE_NON_COMPRESSED_MEMORY`). A booster that allocates a big block forces the kernel to *compress or swap other apps' data* to make room, then releases the block. The "Free" number goes up, but other apps now have to decompress or swap their data back in. Net effect: more work, nothing gained.

### Purgeable memory: already automatic

`vm_stat` shows "Pages purgeable" and "Pages purged" (24 M over uptime). Apps mark this memory volatile on purpose. The kernel throws it away on its own when it needs the space, and `purge(8)` does not touch it. Nothing for Glasswipe to do.

### Quit / relaunch heavy or leaking apps: works

Quitting a process frees all its anonymous memory, including what is compressed or swapped. That is the one thing that reliably raises available memory and shrinks swap. Relaunching helps only when the process has grown (leak, fragmentation, long-lived browser renderer). A fresh process starts small.

How Glasswipe can do it without extra privileges: `NSRunningApplication.terminate()` for a polite quit (the app can save its work), `forceTerminate()` or `kill(2)` only after the user confirms. Same-UID signals need no root.

### Restart per-user background agents: works, sometimes

Same mechanism as relaunching an app. It helps only for agents that have grown. A per-user LaunchAgent can be restarted without root (`launchctl kickstart -k gui/<uid>/<label>`). System daemons need root, and many are SIP-protected. launchd restarts KeepAlive jobs straight away, so killing one gives memory back only if the new instance starts small.

### Raise a fake pressure notification: real but temporary, root only

`memory_pressure -S -l warn|critical` writes `kern.memorypressure_manual_trigger`. The kernel sets the pressure level and sends warn/critical notifications to processes. With the `*_PURGEABLE_*` trigger values it also purges purgeable objects (`bsd/kern/kern_memorystatus_notify.c`, `sysctl_memorypressure_manual_trigger`). Apps that listen (`DispatchSource` memory-pressure sources, `NSCache`, WebKit, libmalloc) drop their caches. The sysctl has no `CTLFLAG_ANYBODY`, so writing it needs **root** (`bsd/kern/kern_newsysctl.c`: "If the flag does not say CTLFLAG_ANYBODY, then we prohibit anyone but root from writing"). This is the only way to "clean RAM" across the whole system that genuinely shrinks other processes without quitting them. But it fakes a signal the kernel would send anyway under real pressure, and apps rebuild their caches. It is worth at most an "advanced" button, not the main feature. (`memory_pressure -l` without `-S` does the opposite: it *allocates* memory until real pressure happens.)

## APIs for the Memory Cleaner's monitoring side

| API | What it gives | Privilege |
|---|---|---|
| `host_statistics64(mach_host_self(), HOST_VM_INFO64, …)` | system page counts (same as `vm_stat`: free, active, inactive, speculative, wired, compressor, purgeable, swapins/outs) | none; `memory_pressure` itself uses it |
| `sysctlbyname("kern.memorystatus_level")` | available % (the pressure input) | none (read) |
| `sysctlbyname("kern.memorystatus_vm_pressure_level")` | current level: 1 normal, 2 warn, 4 critical (dispatch constants) | none on macOS; the `PRIV_VM_PRESSURE` check is `#if !XNU_TARGET_OS_OSX` |
| `sysctlbyname("vm.swapusage")` | swap total/used | none |
| `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` | push notifications when the level changes | none; event-driven, so no polling |
| `proc_listallpids` + `proc_pid_rusage(pid, RUSAGE_INFO_V6, …)` → `ri_phys_footprint` | per-process footprint (what Activity Monitor's Memory column shows) | **same UID only**; other users' processes need root or `PRIV_GLOBAL_PROC_INFO` (`proc_security_policy`, `CHECK_SAME_USER`) |
| `task_info(mach_task_self(), TASK_VM_INFO, …)` → `phys_footprint` | Glasswipe's own footprint | none for its own task; for other tasks you need `task_for_pid`, which needs root plus `com.apple.system-task-ports.*` entitlements (Apple-only in practice) |
| `footprint(1)` / `top(1)` | detailed breakdown / everything | `top` is setuid root with `com.apple.system-task-ports.read`; `footprint -p` worked for an own-UID process and failed for WindowServer (`_windowserver`) without root |

Sources: [xnu `bsd/kern/proc_info.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c) (`proc_pid_rusage`, `proc_security_policy`), [`bsd/kern/kern_memorystatus_notify.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c) (`sysctl_memorystatus_vm_pressure_level`), [`bsd/kern/kern_memorystatus.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus.c) (`kern.memorystatus_level`), [`bsd/kern/kern_newsysctl.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_newsysctl.c), [Apple: DispatchSource.MemoryPressureEvent](https://developer.apple.com/documentation/dispatch/dispatchsource/memorypressureevent), `codesign -d --entitlements` on `/usr/bin/top`.

Glasswipe is unsandboxed and not notarized, so the sandbox MAC hook in `proc_security_policy` does not block it. Unprivileged, it can see and act on every process the user owns, and those are the ones a user can sensibly quit anyway. A privileged helper (`SMAppService` daemon) would only add footprints of system processes and the root-only actions (`purge`, fake pressure), and neither of those earns its cost.

## Recommended Memory Cleaner design (from the evidence)

1. Headline gauge: pressure level (dispatch source plus `kern.memorystatus_vm_pressure_level`), plus compressor size and swap used from `host_statistics64` / `vm.swapusage`. Do **not** feature "Free RAM"; it is misleading by design.
2. Scan: list the user's processes by `ri_phys_footprint`, grouped by app (helpers and renderers rolled up into their parent app), showing the compressed share.
3. Cleanup: quit or relaunch the selected apps and agents after approval (polite terminate first). Show the before/after change in compressor and swap as proof.
4. Leave out `purge`. Maybe an advanced "ask apps to release caches" option that uses the root-only pressure trigger, if a helper ever exists for something else.

## Caveats

- XNU `main` on GitHub is the newest open-source drop. It may be behind the shipping kernel. The formula was checked against live numbers on a test Mac; the exact thresholds (`vm_compressor_*_threshold_divisor`) are not exposed through sysctl here.
- Apple's DispatchSource page renders client-side and could not be fetched as text. The level constants come from the kernel's dispatch-level conversion and `sys/event.h` usage in XNU.
- Nothing destructive was run: no `purge`, no `memory_pressure -l/-S`, no process killed.
