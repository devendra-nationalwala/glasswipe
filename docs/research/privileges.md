# Full Disk Access and admin rights for a personal, unnotarized build

Research for [#6](https://github.com/devendra-nationalwala/glasswipe/issues/6). Researched 2026-11-07.

Context: Glasswipe is a personal, open-source build for Apple Silicon Macs on macOS 26 and later. It never ships through the App Store and is never notarized. The author may have a free Apple Account (Xcode "Personal Team") or a paid Apple Developer Program membership.

Sources are Apple documentation and Apple Developer Forums posts by Apple DTS (Quinn "The Eskimo!"). Every claim cites its source. Points marked **Unverified** have no primary source and need a prototype on the real machine.

## Answer in brief

1. **Signing decides everything.** TCC records an app's *designated requirement* (DR) and checks each new build against it. Ad hoc signing ("Sign to Run Locally") gives a DR tied to that one build, so every rebuild loses its Full Disk Access (FDA) grant. Sign every build with one stable identity. An **Apple Development** identity does this, and Xcode creates one for a free Personal Team too. [S1][S2][S3][S4]
2. **There is no API to check for FDA or to ask for it.** The only exception is Endpoint Security clients, which Glasswipe is not. The workable approach: try to read a file that FDA protects, treat `EPERM` as "no FDA", and send the user to the FDA pane in System Settings. [S5][S6][S7]
3. **Root does not get around TCC.** A root helper still needs FDA, and TCC shows no prompt for a launchd daemon. [S6][S8]
4. **Privileged deletes.** For a single-user personal tool, Apple DTS puts the choices in this order:
   - **SMAppService daemon plus XPC.** The right design for ongoing privilege. It needs an Apple-issued identity, the same one on the app and the helper. Ad hoc signing fails here.
   - **AppleScript `do shell script … with administrator privileges`.** The simplest way to get privilege once, and DTS lists it as acceptable for an ad hoc or limited audience.
   - **`AuthorizationExecuteWithPrivileges`.** Deprecated since macOS 10.7. DTS also lists it as acceptable for a limited audience.
   - **Never** use setuid-root. **Never** run the GUI as root. [S8][S9][S10]
5. **App Management.** Even as root, changing or deleting *another developer's notarized app bundle* can be blocked by the App Management privilege. There is no API to request that privilege. [S11][S12][S13]

## 1. Code signing and whether TCC grants survive rebuilds

| Signing | Stable DR across rebuilds? | TCC grants survive rebuilds? | SMAppService daemon works? | Account needed |
|---|---|---|---|---|
| Unsigned | No | No | No | None |
| Ad hoc (`codesign -s -`, "Sign to Run Locally") | No (DR is tied to the cdhash of that build) | No: re-grant FDA after every build | No ("you will see problems like this") | None |
| Self-signed code-signing certificate (made in Keychain Access) | Yes, while the certificate lasts (the default DR pins the leaf certificate hash) | Yes, in principle | **Unverified.** DTS says an "Apple-issued" identity | None |
| Apple Development (Xcode-managed) | Yes. The DR uses Apple's anchor plus the leaf certificate's subject CN | Yes | Yes | Free Personal Team or paid |
| Developer ID Application | Yes | Yes | Yes | Paid only |

Evidence:

- "The signing identity is used as a component of the designated requirement (DR), and TCC uses the DR to track whether build N+1 of your program is the same as build N." [S1]
- "For MAC to work it has to be able to identify build N+1 of your app as being the 'same code' as build N … An Apple Development code signing identity works for that. The two things that don't are unsigned code and ad hoc signed code." [S2]
- "Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but it's tied to that specific version of the code." TN3127 also gives the Apple Development DR form (`anchor apple generic and certificate leaf[subject.CN] = "Apple Development: …" and certificate 1[field.1.2.840.113635.100.6.2.1]`). It warns that switching between Apple Development and Developer ID variants triggers a new prompt, because their DRs differ. [S3]
- "Sign your code with a stable code-signing identity, ideally one issued by Apple." The words "ideally one issued by Apple" leave room for a self-signed identity where only TCC is involved. [S4]
- With a non-Apple certificate, codesign's default DR is `identifier "…" and certificate leaf = H"<hash>"`. Renewing the certificate therefore changes the DR. [S14]
- Free Apple Accounts get an Xcode Personal Team, which can sign with an Apple Development identity for apps on your own devices. They have no access to Certificates, Identifiers & Profiles, Developer ID or notarization. Their provisioning profiles expire after 7 days. [S15][S16]

**Free vs paid for Glasswipe:**
- **Free account:** Apple Development signing works and gives a stable DR. A plain macOS app with no restricted entitlements needs no provisioning profile, so the 7-day expiry should not matter for Glasswipe. (**Unverified** for this exact setup. Confirm with a prototype.) Developer ID and notarization are not available, and Glasswipe needs neither: a locally built app has no quarantine flag, so Gatekeeper does not check it at first launch.
- **Paid account:** Adds Developer ID. That only matters for distributing builds to other people. The Apple Development identity covers personal use. Switching identities later triggers one new round of TCC grants. [S3]
- **No account:** Use a long-lived self-signed code-signing certificate for a stable TCC DR. Expect SMAppService daemons not to work.

## 2. Checking for and asking for Full Disk Access

- "Except in very limited circumstances, there's no good way to: Tell if you have the Full Disk Access privilege; Explicitly ask for the privilege." (DTS, Oct 2023.) The exception is Endpoint Security: `es_new_client` returns `ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED`. DTS also points to `<EndpointSecurity/ESClient.h>` as the documented way to open the FDA editor in System Settings. [S5]
- Blocked by MAC/TCC: the call fails with `EPERM` (1). Blocked by BSD permissions or ACLs: it fails with `EACCES` (13). FDA applies to the whole system, not to one user. Root is also subject to MAC. [S6]
- Reading `TCC.db` directly is a test hack, not a supported check. Its location and format are implementation details. [S7]

**Recommended approach for Glasswipe:**
1. At launch and before each Scan, try a read-only probe of a location that FDA protects, for example listing `~/Library/Mail` or `~/Library/Safari`, or opening `/Library/Application Support/com.apple.TCC/TCC.db` read-only. `EPERM` means no FDA. Success means FDA. (Which paths are protected is not documented, so probe more than one. **Unverified** on macOS 27.)
2. If FDA is missing, explain why it's needed and open the pane at `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. (This URL is used widely and is the one `ESClient.h` gives. **Unverified** that it still lands on the right pane in macOS 27's System Settings.)
3. The user has to add Glasswipe.app manually (with the + button or by dragging it in). After that, macOS may require Glasswipe to relaunch.
4. Sign every build with the same identity, or step 3 repeats after every build. [S1][S2]

## 3. Privileged deletes: the options

TCC first: "Escalating privileges does not bypass all privilege restrictions … MAC applies to all processes, including those running as root. Indeed, running as root can make things harder because TCC will not display UI when a launchd daemon trips over a MAC restriction." [S8]

On attribution: TCC looks for the *responsible code*. For a daemon installed with SMAppService, the installing app is the responsible code. Otherwise, add `AssociatedBundleIdentifiers` to the launchd plist. The algorithm "is not documented, has changed in the past, and may well change in the future." [S6][S17] So whether Glasswipe.app's FDA grant covers its helper must be checked on the real machine (**Unverified**).

| Option | Status | Fits a personal unsigned or dev-signed build? | Trade-offs |
|---|---|---|---|
| **SMAppService.daemon + NSXPCConnection** | Current API, macOS 13+. DTS recommends it for ongoing privilege. [S8][S9] | Only with an Apple-issued identity on both the app and the daemon, with matching team ID. Ad hoc fails. [S10] | Approve once ("Background Items Added", then Allow and authenticate). After that, no password prompts. Most code: XPC protocol, client check (`setCodeSigningRequirement`), user authorization through Authorization Services. The helper is a permanent root attack surface. The plist lives in `Contents/Library/LaunchDaemons` with `BundleProgram`. A sandboxed app can't install an unsandboxed daemon. Debug with `sfltool resetbtm` and `sudo launchctl`. [S8][S9][S10][S18] |
| **AppleScript `do shell script … with administrator privileges`** (through `NSAppleScript`/`osascript`) | Supported. DTS lists it for one-off privilege for an "ad hoc/limited audience". [S8] | Yes, with any signing. | Password prompt on every privileged action. Very little code. Shell quoting is a real injection risk: always use `quoted form of` and pass paths as arguments, as in DTS's sample. Hard to stream progress or handle errors in detail. TCC attribution of the spawned shell is **Unverified**. [S8] |
| **`AuthorizationExecuteWithPrivileges`** | Deprecated since macOS 10.7. DTS still lists it as acceptable for a limited audience. [S8] | Yes, with any signing. | Prompt each time. Deprecated C API (importing it into Swift is **Unverified**). No real advantage over AppleScript. Could disappear in a future release. |
| **`SMJobBless`** | Deprecated since macOS 13. [S8] | Needs Apple-issued signing and `SMPrivilegedExecutables`/`SMAuthorizedClients` requirements | No reason to use it on macOS 26+. |
| **Installer package (.pkg)** | Supported. DTS calls it "by far the easiest" for install-time privilege. [S8] | Yes | Only helps at install time, for example to install a daemon. Doesn't fit on-demand Cleanup. |
| **NSWorkspace privileged file operations** | Supported. [S8][S19] | Needs a restricted entitlement that Apple grants on request | Covers only symlink, replace and set-attributes. **Not delete.** Not usable. |
| **setuid-root tool** | "Do not use a setuid-root executable. Ever." [S8] | n/a | Rejected. |
| **Running the GUI as root** | "not supported and not safe" [S8] | n/a | Rejected. |

**Recommendation by account:**
- **Paid or free account (Apple Development identity):** Design for an SMAppService daemon that does only the privileged deletes. Keep the helper small: an allowlist of operations, paths checked on the root side, and the client's code signature checked. Most Junk under `~/Library` needs no root at all, only FDA. Root matters only for `/Library`, `/private/var` and root-owned app bundles, so the helper can come after the MVP.
- **No account, or until the helper exists:** Use AppleScript `with administrator privileges` for the rare root-only Cleanup items, batched into one prompt per Cleanup.

## 4. App Management (relevant to Uninstall)

- Since macOS 13, Gatekeeper checks the integrity of all notarized apps. "If an app is modified by something that isn't signed by the same development team and isn't allowed by an NSUpdateSecurityPolicy, macOS will block the modification and notify the user that an app wants to manage other apps." [S11]
- This appears in System Settings as Privacy & Security > App Management. "Is there a way to request App Management permission via API?" DTS: "No." [S12][S13]
- Whether *deleting* a whole bundle counts as modification is not covered in the WWDC session (**Unverified**). Glasswipe should expect the App Management prompt during Uninstall and guide the user to grant it, the same way as for FDA. A daemon running as root is also subject to it, because it is MAC.

## Sources

- [S1] Apple Developer Forums, DTS, "Network share access prompt after every compile": https://developer.apple.com/forums/thread/707177
- [S2] Apple Developer Forums, DTS, "Full Disk Access, Run and Debug from Xcode?": https://developer.apple.com/forums/thread/696586
- [S3] TN3127: Inside Code Signing: Requirements: https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
- [S4] Apple Developer Forums, DTS, "Why does my app lose Screen Recording permission after updating (adhoc signature)?": https://developer.apple.com/forums/thread/795739
- [S5] Apple Developer Forums, DTS, "Is there any API for Full Disk Access in MacOS?": https://developer.apple.com/forums/thread/739236
- [S6] Apple Developer Forums, DTS, "On File System Permissions": https://developer.apple.com/forums/thread/678819
- [S7] Apple Developer Forums, "Reliable test for Full Disk Access?": https://developer.apple.com/forums/thread/114452
- [S8] Apple Developer Forums, DTS, "BSD Privilege Escalation on macOS" (updated 2025-03-24): https://developer.apple.com/forums/thread/708765
- [S9] SMAppService documentation: https://developer.apple.com/documentation/servicemanagement/smappservice and `daemon(plistName:)`: https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)
- [S10] Apple Developer Forums, DTS, "SMAppService Sample Code seems broken": https://developer.apple.com/forums/thread/799910
- [S11] WWDC22 "What's new in privacy" (app bundle protection): https://developer.apple.com/videos/play/wwdc2022/10096/
- [S12] Apple Developer Forums, DTS, "New 'App Management' privacy setting in Ventura": https://developer.apple.com/forums/thread/715220
- [S13] Apple Developer Forums, DTS, "Is there a way to request App Management permission via API": https://developer.apple.com/forums/thread/720936
- [S14] Apple Developer Forums, "Stable designated requirements across cert renewal": https://developer.apple.com/forums/thread/50955
- [S15] Apple, "Choosing a Membership": https://developer.apple.com/support/compare-memberships/
- [S16] Technical Q&A QA1915 (Personal Team limits): https://developer.apple.com/library/archive/qa/qa1915/_index.html
- [S17] Apple Developer Forums, DTS, "How to grant command line tools full disk access": https://developer.apple.com/forums/thread/756510
- [S18] Apple Developer Forums, DTS, "Getting Started with SMAppService" (Sept 2025): https://developer.apple.com/forums/thread/802443 and "How to authorize LaunchDaemons": https://developer.apple.com/forums/thread/761249
- [S19] Entitlement `com.apple.developer.security.privileged-file-operations`: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.security.privileged-file-operations
