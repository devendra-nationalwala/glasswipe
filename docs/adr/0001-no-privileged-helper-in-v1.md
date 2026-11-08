# No privileged helper in v1; one admin prompt per Cleanup

Almost all Junk worth cleaning lives in the home folder and needs at most Full Disk Access, while the admin-only locations (`/Library/Caches`, `/Library/Logs`, system launch daemons) hold about 200 MB on a typical Mac. A root `SMAppService` helper would remove the password prompt but needs an Apple-issued signature on both the app and the helper, a hardened XPC interface and its own security review. So v1 runs the few admin-only removals as one AppleScript `do shell script … with administrator privileges` call per Cleanup, and every path still passes the Safety Gate first.

## Consequences

- The user types their password once per Cleanup that touches system folders.
- Revisit if admin-only features grow (for example a scheduled system cleanup), which would justify the helper.
