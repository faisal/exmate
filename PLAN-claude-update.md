# TextMate Modernization: Review & Completion Plan

## Context

PRs 1-10 and PR 11 (sub-commits 11a-11o) are committed. Parts 1 and 2 are **complete** — the build succeeds with **zero warnings** (all remaining deprecations are either migrated or suppressed with documented TODOs). The mkstemp fix, indentation fixes, @available guard removal, HOJSBridge cleanup, dead WebView removal, and all deprecation warning fixes are committed.

Remaining work: PRs 12-15 (interface layout metrics, tests/CI, Xcode build integration, documentation).

---

## Remaining Warning Suppressions

PRs 11g–11o are committed. The build is **zero warnings**. All remaining suppressions fall into three categories:

### A. Suppressions Added by This Modernization (8 pragma blocks)

#### 1. SecTransform — DSA Signature Verification (2 files)
- `Frameworks/network/src/filter_check_signature.cc`
- `Frameworks/SoftwareUpdate/src/OakDownloadManager.mm`

**What's suppressed:** `SecVerifyTransformCreate`, `SecTransformSetAttribute`, `SecTransformExecute` — the old cryptographic transform pipeline for signature verification.

**Why suppressed:** `SecKeyVerifySignature` (the modern replacement) does not support DSA keys. TextMate's update signing keys (`org.textmate.duff`, `org.textmate.msheets`) are DSA-1024/2048 keys, decoded from base64 DER — the `GByqGSM` prefix in `updater.cc` corresponds to OID `1.2.840.10040.4.1` (DSA).

**What migration requires:**
1. Generate new ECDSA P-256 or RSA-PSS signing keys for TextMate updates
2. Update the build pipeline that signs `.tbz` updates to use the new key
3. Ship a transition release that trusts both old DSA and new ECDSA signatures (so existing users with old keys can verify the transition update)
4. After the transition window, remove the DSA path and drop the pragma suppression
5. Estimated effort: **medium** — the C++ verification code changes are ~20 lines, but key rotation and the distribution pipeline are the hard parts

#### 2. NSConnection — Distributed Objects IPC (6 locations, 5 files)
- `Frameworks/CommitWindow/src/CommitWindow.mm` (3 pragma blocks)
- `PlugIns/dialog/Dialog2.mm` (2 pragma blocks)
- `PlugIns/dialog/tm_dialog2.mm` (1 pragma block)
- `PlugIns/dialog-1.x/Dialog.mm` (2 pragma blocks)
- `PlugIns/dialog-1.x/tm_dialog.mm` (1 pragma block)

**What's suppressed:** `NSConnection` and its DO (Distributed Objects) machinery — `rootProxyForConnectionWithRegisteredName:host:`, `setProtocolForProxy:`, `registerName:`, and the NSConnection property declarations.

**Why suppressed:** NSConnection is the foundational IPC mechanism for the dialog plugin and CommitWindow. The entire architecture — `@protocol OakCommitWindowClientProtocol`, proxy method dispatch, port registration — is built around Distributed Objects. There is no drop-in modern equivalent.

**What migration requires:**
- Replace NSConnection with **NSXPCConnection** (the modern XPC-based IPC system)
- `NSXPCConnection` uses a different connection model: each end registers a listener/endpoint, not a port name
- All protocol methods must be redesigned: DO allows passing arbitrary objects by reference; XPC requires explicit serialization (NSSecureCoding) for all types
- For `CommitWindow`: the server (`OakCommitWindowServer`) and client (`OakCommitWindowClient`) protocols need `NSXPCInterface` wrappers; all callbacks require explicit reply blocks
- For `dialog` plugins: `tm_dialog2` and `Dialog2` use a pipe + DO hybrid; the pipe part stays but the proxy registration changes entirely
- Estimated effort: **large** — roughly a 2–3 day rewrite; semantically equivalent but structurally different in all 5 files

#### 3. QuickLook Generator API (1 file, file-level pragma)
- `Applications/QuickLookGenerator/src/generate.mm`

**What's suppressed:** `QLThumbnailRequestGetGeneratorBundle`, `QLThumbnailRequestIsCancelled`, `QLThumbnailRequestCreateContext`, `QLThumbnailRequestFlushContext`, `QLPreviewRequestGetGeneratorBundle`, `QLPreviewRequestSetDataRepresentation`, `QLPreviewRequestIsCancelled` — the entire legacy QLGenerator plugin interface.

**Why suppressed:** The replacement architecture (`QLPreviewingController` / `QLThumbnailReply`) is a fundamentally different programming model — an app extension rather than a bundle-based plugin.

**What migration requires:**
- Create a new **QuickLook Preview Extension** target (`.appex`) using `QLPreviewingController`
- Create a separate **Thumbnail Extension** target using `QLFileThumbnailRequest` and `QLThumbnailReply`
- Both must be app extensions (sandboxed, no direct file system access without entitlements), so the bundle loading code and settings file paths need redesign
- The existing rendering logic (syntax highlighting, RTF generation) can be reused
- Drop `plugin.h` / `QLGenerator` bundle structure entirely; add both extensions to `TextMate.app`
- Estimated effort: **large** — the rendering code (~150 lines) stays, but the scaffolding changes completely

### B. Pre-existing Suppressions (2 files, existed before this modernization)

#### 4. AuthorizationExecuteWithPrivileges (scope narrowed by us)
- `Shared/include/oak/compat.h`

**What's suppressed:** `AuthorizationExecuteWithPrivileges` — runs a helper tool with root privileges.

**What migration requires:** Replace with `SMJobBless` (uses a registered launchd job) or a persistent XPC service. This is non-trivial because `SMJobBless` requires the helper to be a separate bundle with a specific Info.plist structure, code-signed, and registered with launchd. Estimated effort: **medium**.

#### 5. FSRef / Resource Manager / Carbon APIs (pre-existing)
- `Frameworks/io/src/resource.cc`

**What's suppressed:** `FSPathMakeRefWithOptions`, `FSOpenResFile`, `Get1Resource`, `HLock`/`HUnlock`, `GetHandleSize`, `ReleaseResource`, `CloseResFile` — Carbon-era resource fork reading for `.textClipping` files.

**What migration requires:** Replace with `[[NSFileWrapper alloc] initWithURL:options:error:]` or low-level `getxattr`/`copyfile` to read resource forks. The data format (type/creator codes, resource types `'TEXT'`/`'utxt'`) still needs to be parsed manually. Estimated effort: **small-medium** (the API is deprecated but the data format is well-known).

### C. Vendor Build-Flag Suppressions (acceptable, third-party code)

| File | Flag | Reason |
|------|------|--------|
| `vendor/kvdb/default.rave` | `-Wno-deprecated-declarations` | Third-party SQLite-backed KV store; not our code to fix |
| `vendor/capnp/default.rave` | `-Wno-deprecated-this-capture` | Cap'n Proto serialization library; upstream fix pending |

These are appropriate for external dependencies and do not represent technical debt in TextMate's own code.

### Suppression Summary

| # | Suppressed API | Files | Effort | Blocked by |
|---|---------------|-------|--------|------------|
| 1 | SecTransform (DSA) | 2 | Medium | Key rotation infrastructure |
| 2 | NSConnection (DO) | 5 | Large | Full IPC rewrite |
| 3 | QLGenerator API | 1 | Large | Extension architecture rewrite |
| 4 | AuthorizationExecuteWithPrivileges | 1 | Medium | SMJobBless/XPC redesign |
| 5 | FSRef / Carbon Resource Manager | 1 | Small-Medium | — |
| 6 | Vendor (kvdb, capnp) | 2 | None | Upstream fixes |

The pragmas are sound: each has a `// TODO:` comment explaining what would be required. None suppress active bugs — they suppress warnings about deprecated-but-still-functional APIs that would require architectural rewrites to replace.

---

## Future TODO: Replace kvdb with Couchbase Lite

kvdb (upstream [colinyoung/kvdb](https://github.com/colinyoung/kvdb), abandoned ~2013) is used by `DocumentWindowController.mm` and `Favorites.mm` to persist project state in `RecentProjects.db`. The vendored copy at v0.0.8 has 3 deprecated `NSKeyedArchiver`/`NSKeyedUnarchiver` calls, currently suppressed with `-Wno-deprecated-declarations`.

[Couchbase Lite](https://github.com/couchbase/couchbase-lite-ios) (v4.0.3, macOS 13.0+, actively maintained) could replace it but is significant overkill (~50–100 MB xcframework vs 439 lines, requires rave xcframework support, API rewrite, data migration). Consider either: (a) fixing the 3 deprecated calls in-place as a stop-gap, or (b) replacing kvdb with Couchbase Lite as a larger future project.

---

## Completed: Part 1 — Fixes to Existing Work

*All items committed.*

- **1a.** Fixed FSEventStream deadlock — removed `FSEventStreamFlushSync()` calls in `events.cc` and `fs_events.cc`
- **1b.** Committed mkstemp→unlink fix in `path.cc`
- **1c.** Fixed indentation in `tokenize.h` and `utf8.h`
- **1d.** Fixed HOJSBridge duplicate category in `HOJSBridge.h`/`.mm`
- **1e.** Removed dead WebView code in `HOJSBridge.mm` and `OakCommand.mm`
- **1f.** Removed 31 `@available` guards across 22 files

---

## Completed: Part 2 — PR 11 (Remaining Deprecation Warnings)

*All sub-commits 11g–11o committed. Build is zero warnings.*

- **11g:** Trivial renames (`NSBackgroundStyleDark`, `iconForFileType:`, `openFile:`, etc.)
- **11h:** NSUserNotification → UNUserNotificationCenter in CrashReporter.mm
- **11i:** Added `<NSEditor>` protocol conformance in BundleEditor.mm, Find.mm
- **11j:** `launchApplicationAtURL:` → `openApplicationAtURL:` in OakOpenWithMenu.mm
- **11k:** NSKeyedArchiver/Unarchiver modernization in FileBrowserViewController.mm
- **11l:** SecTransform → pragma suppression (DSA keys require key rotation — see Suppressions §1)
- **11m:** SecKeychain → SecItem in proxy.cc, keychain.cc
- **11n:** Dialog submodule fixes (UTType, ValueTransformers, NSConnection suppression)
- **11o:** QuickLook pragma, unused variables, vendor build flags, REFERENCED_DYNAMICALLY fix

---

## Part 3: PR 12 — Interface Layout Metrics

Requires visual comparison between the modernized build and the prior TextMate version.

**Files:**
- `Frameworks/OakTabBarView/src/OakTabBarView.mm` — tab bar height/drawing
- `Frameworks/FileBrowser/src/OFB/OFBHeaderView.mm` — file browser header
- `Frameworks/HTMLOutput/src/browser/HOStatusBar.mm` — HTML output status bar
- `Frameworks/OakTextView/src/OTVStatusBar.mm` — editor status bar
- `Frameworks/OakAppKit/src/OakUIConstructionFunctions.mm` — UI helpers
- `Frameworks/DocumentWindow/src/DocumentWindowController.mm` — main window
- `Frameworks/Preferences/src/Preferences.mm` — prefs window

**Approach:**
1. Build and run the modernized TextMate, screenshot key UI areas (tab bar, sidebar, status bars, preferences) in light + dark mode
2. Ask user to take the same screenshots with the prior/released TextMate version
3. Compare side-by-side and identify discrepancies in metrics, vibrancy, colors
4. Adjust hardcoded metrics, `NSVisualEffectView` materials, toolbar styles, and colors to match

---

## Part 4: PR 13 — Tests + CI

New tests for modernized APIs:
- OS version detection (`oak::os_major() >= 13`)
- posix_spawn fd handling / process groups
- UTType icon resolution
- WKWebView JS bridge + URL scheme handler
- Layout constraint satisfaction
- Dark mode smoke test

CI: `.github/workflows/build.yml` with `macos-14` runner.

---

## Part 5: PR 14 — Xcode Build Integration

The stash (`stash@{0}`) has reference Xcode scheme files and project changes from an earlier attempt. Use as reference only — generate fresh with `xcodegen` from `project.yml`.

**Steps:**
1. Update `project.yml` with auto-detected Xcode version
2. Run `xcodegen generate` to produce `TextMate.xcodeproj`
3. Add scheme files for all targets
4. Verify `xcodebuild build -scheme TextMate`

---

## Part 6: PR 15 — Documentation & Cleanup

- Update `README.md` with macOS 13.0+ requirement, vendored capnp, tool list including xcodegen
- Remove stale `#pragma` suppressions no longer needed
- Clean up any remaining dead code
- Verify `.gitmodules` points dialog to `faisal/exmate-dialog.git`, dialog-1.x to `faisal/exmate-dialog-1.x.git`

---

## Verification

After each commit group, run:
```bash
ninja   # from project root — full build
```
Check warning count is decreasing:
```bash
ninja 2>&1 | grep -c "warning:"
```
After all PR 11 work: warning count should be near-zero (only documented suppressions).

After PR 12: run app, visually verify UI in light + dark mode.

After PR 14: `xcodebuild build -scheme TextMate -configuration Debug` should succeed.
