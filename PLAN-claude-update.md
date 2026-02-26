# TextMate Modernization: Review & Completion Plan

## Context

PRs 1-10 and parts of PR 11 (sub-commits 11a-11f) are committed. The build succeeds but produces **~91 warnings** (86 deprecation + 5 code quality). Additionally, earlier PRs left some items incomplete (31 `@available` guards, indentation defects in header files, dead WebView code). The mkstemp→unlink fix in `path.cc` is applied but uncommitted.

This plan covers: (1) fixes to existing work, (2) completing PR 11, (3) PRs 12-15.

---

## Part 1: Fixes to Existing Work (Blockers First)

### 1a. Fix FSEventStream deadlock causing launch hang (PR 11f regression)

PR 11f replaced `FSEventStreamScheduleWithRunLoop` with `FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue())`. But two call sites still call `FSEventStreamFlushSync()` from the main thread immediately after. This is a **classic GCD deadlock**: FlushSync blocks the main thread waiting for callbacks, but callbacks are queued on `dispatch_get_main_queue()` which can't run because the main thread is blocked.

**Affected files:**
- `Frameworks/io/src/events.cc:125-128` — `FSEventStreamSetDispatchQueue` + `FSEventStreamFlushSync`
- `Frameworks/scm/src/fs_events.cc:25-27` — same pattern

**Fix:** Remove the `FSEventStreamFlushSync()` calls in both files. The flush was useful with RunLoop scheduling (FlushSync pumps the run loop inline), but with GCD dispatch to the main queue it deadlocks. Events will still be delivered asynchronously after `FSEventStreamStart()`.

`Frameworks/FileBrowser/src/FSEventsManager.mm:44` uses `FSEventStreamSetDispatchQueue` but does NOT call FlushSync, so it's fine.

### 1b. Commit the mkstemp fix in path.cc
Already applied — `unlink(str.c_str())` after `mkstemp`+`close` in `Frameworks/io/src/path.cc:864-868`. Commit this.

### 1c. Fix broken indentation from PR 11b (iterator modernization)

**`Frameworks/text/src/tokenize.h`** — The `tokenize_helper_t` struct body is over-indented (2 tabs inside namespace, should be 1). The `using` declarations inside `iterator` are at 4 tabs while the remaining members (constructor, operators, private) are at 3 tabs. All members inside `iterator` should be at a consistent indent level.

**`Frameworks/text/src/utf8.h`** — In the `diacritics` namespace (~line 247), `iterator_t` template+struct are at 2 tabs (should be 1), and the `using` declarations are at the same level as the struct's opening brace (should be one level deeper).

These are whitespace-only fixes. No logic changes.

### 1d. Fix HOJSBridge duplicate category + incompatible pointer type (from PR 10)

**`Frameworks/HTMLOutput/src/helpers/HOJSBridge.h:16`** — Change to:
```objc
@interface HOJSBridge (WKWebView) <WKScriptMessageHandler>
```

**`Frameworks/HTMLOutput/src/helpers/HOJSBridge.mm:33`** — Remove the duplicate `@interface HOJSBridge (WKWebView) <WKScriptMessageHandler>` declaration.

This fixes both the `-Wobjc-duplicate-category-definition` warning and the `-Wincompatible-pointer-types` warning in `HOBrowserView.mm:35` (because the header will now properly declare the protocol conformance).

### 1e. Remove dead WebView code left from PR 10

**`Frameworks/HTMLOutput/src/helpers/HOJSBridge.mm:115`** — Replace `[WebUndefined class]` check with `[NSNull class]` (in WKWebView, undefined JS values arrive as `NSNull`).

**`Frameworks/OakCommand/src/OakCommand.mm:699-707`** — Delete the entire `+load` method that calls `[WebView registerURLSchemeAsLocal:]` with its pragma suppression. PR 10 migrated to `WKURLSchemeHandler`; this is dead code.

### 1f. Remove 31 remaining `@available` guards (should have been done in PR 1)

All guards check for macOS 10.13/10.14/10.15/11.0 — all below the 13.0 minimum. For each: take the true-branch, delete the `if(@available(...))` wrapper and the `else` branch.

Files (31 guards across 22 files):
- `Applications/QuickLookGenerator/src/generate.mm` (1)
- `Applications/TextMate/src/OakMainMenu.mm` (1)
- `Frameworks/OakTabBarView/src/OakTabBarView.mm` (3)
- `Frameworks/BundleEditor/src/BundleEditor.mm` (1)
- `Frameworks/Find/src/FFResultsViewController.mm` (1)
- `Frameworks/MenuBuilder/src/MenuBuilder.mm` (1)
- `Frameworks/FileBrowser/src/FileBrowserView.mm` (1)
- `Frameworks/Preferences/src/Preferences.mm` (1)
- `Frameworks/Preferences/src/SoftwareUpdatePreferences.mm` (1)
- `Frameworks/Preferences/src/BundlesPreferences.mm` (1)
- `Frameworks/SoftwareUpdate/src/OakDownloadManager.mm` (2)
- `Frameworks/CrashReporter/src/CrashReporter.mm` (2)
- `Frameworks/OakAppKit/src/OakTransitionViewController.mm` (1)
- `Frameworks/OakAppKit/src/OakKeyEquivalentView.mm` (1)
- `Frameworks/OakAppKit/src/OakToolTip.mm` (1)
- `Frameworks/OakAppKit/src/OakUIConstructionFunctions.mm` (3)
- `Frameworks/OakAppKit/src/NSMenuItem Additions.mm` (1)
- `Frameworks/OakAppKit/src/OakPasteboardChooser.mm` (1)
- `Frameworks/OakFilterList/src/OakChooser.mm` (1)
- `Frameworks/OakTextView/src/OTVStatusBar.mm` (1)
- `Frameworks/OakTextView/src/OakTextView.mm` (1)
- `Frameworks/OakTextView/src/OakChoiceMenu.mm` (2)
- `PlugIns/dialog/Commands/popup/TMDIncrementalPopUpMenu.mm` (2)

---

## Part 2: Complete PR 11 (Remaining Deprecation Warnings)

Group the ~86 remaining deprecation warnings into sub-commits by complexity.

### 11g: Trivial renames (11 warnings)

Direct symbol renames with identical semantics:

| Old | New | Files |
|-----|-----|-------|
| `NSBackgroundStyleDark` | `NSBackgroundStyleEmphasized` | OakPasteboardChooser.mm, FFResultsViewController.mm, OakChooser.mm, TableView.mm, BundleItemChooser.mm |
| `alternateSelectedControlColor` | `selectedContentBackgroundColor` | TableView.mm |
| `iconForFileType:` | `iconForContentType:` (with UTType) | NSMenuItem Additions.mm, BundleEditor.mm, BundlesPreferences.mm |
| `openFile:` | `openURL:` | FileBrowserViewController.mm |
| `NSAccessibilityException` | Remove or replace with NSRangeException | SearchField.mm |

### 11h: NSUserNotification → UserNotifications (CrashReporter.mm)

The file already has the UNUserNotificationCenter code behind `@available(10.14)` guards. After Part 1e removes those guards, delete the `NSUserNotification` fallback paths and the `NSUserNotificationCenterDelegate` conformance. Also replace `UNNotificationPresentationOptionAlert` → `UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList`.

**File:** `Frameworks/CrashReporter/src/CrashReporter.mm`

### 11i: commitEditing NSEditor protocol (8 warnings)

Add `<NSEditor>` protocol conformance to class interfaces that call `[self commitEditing]`:
- `Frameworks/BundleEditor/src/BundleEditor.mm`
- `Frameworks/Find/src/Find.mm`

### 11j: NSWorkspace launchApplicationAtURL → openApplicationAtURL (3 warnings)

Replace `launchApplicationAtURL:options:configuration:error:` with `NSWorkspaceOpenConfiguration` + `openApplicationAtURL:configuration:completionHandler:` in `Frameworks/OakAppKit/src/OakOpenWithMenu.mm`.

### 11k: NSKeyedArchiver/Unarchiver in FileBrowserViewController (2 warnings)

- `[[NSKeyedArchiver alloc] init]` → `[[NSKeyedArchiver alloc] initRequiringSecureCoding:NO]`
- `initForReadingWithData:` → `initForReadingFromData:error:`

**File:** `Frameworks/FileBrowser/src/FileBrowserViewController.mm`

### 11l: SecTransform → SecKeyVerifySignature (10 warnings)

Replace the 3-step `SecVerifyTransformCreate`/`SecTransformSetAttribute`/`SecTransformExecute` pattern with the single `SecKeyVerifySignature()` call (available since macOS 10.12).

**Files:**
- `Frameworks/network/src/filter_check_signature.cc`
- `Frameworks/SoftwareUpdate/src/OakDownloadManager.mm`

### 11m: SecKeychain → SecItem (4 warnings)

Replace `SecKeychainItemCopyAttributesAndData`/`SecKeychainItemFreeAttributesAndData` with `SecItemCopyMatching` using `kSecReturnAttributes` + `kSecReturnData`.

**Files:**
- `Frameworks/network/src/proxy.cc`
- `Frameworks/license/src/keychain.cc`

### 11n: Dialog submodule deprecation fixes (4 warnings migrated + 12 suppressed)

**Migrate (trivial swaps):**
- `javaScriptEnabled = YES` → remove (default is YES in WKWebView) — `TMDHTMLTips.mm`
- `setAllowedFileTypes:` → `allowedContentTypes` with UTType — `filepanel.mm`
- `colorUsingColorSpaceName:` → `colorUsingColorSpace:[NSColorSpace sRGBColorSpace]` — `ValueTransformers.mm` (both dialog and dialog-1.x)

**Suppress with documented TODO (NSConnection — fundamental IPC architecture):**
Add pragma suppression + TODO comment in: `Dialog.mm`, `Dialog2.mm`, `tm_dialog.mm`, `tm_dialog2.mm`, `CommitWindow.mm`, `commit.mm`

**Submodule workflow:**
- `dialog`: Push changes to `faisal/exmate-dialog.git` on branch `sdk_update_three`. Update `.gitmodules` to point there.
- `dialog-1.x`: Push changes to existing `faisal/dialog-1.x.git` fork (reuse as-is, don't rename).

### 11o: QuickLook + miscellaneous + vendor suppressions (~18 warnings)

**QuickLook generator (9 warnings):** Suppress with pragma + TODO (migration requires rewrite to QLPreviewingController extension architecture). Fix the two non-QL warnings in same file:
- `graphicsContextWithGraphicsPort:flipped:` → `graphicsContextWithCGContext:flipped:`
- `currentAppearance` → `currentDrawingAppearance` or `NSApp.effectiveAppearance`

**3 unused variable warnings:** Fix in `PrivilegedTool/main.cc`, `OakPasteboard.mm`, `Favorites.mm`.

**kvdb NSKeyedArchiver (3 warnings):** Add `-Wno-deprecated-declarations` to kvdb target compile flags (submodule — avoids forking for 3 warnings).

**capnp vendor warnings:** Add `-Wno-deprecated-this-capture` to kj target compile flags.

**Linker warning (`REFERENCED_DYNAMICALLY`):** Investigate `__crashreporter_info__` symbol, remove attribute if possible.

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
- Verify `.gitmodules` points dialog to `faisal/exmate-dialog.git`, dialog-1.x to `faisal/dialog-1.x.git`

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
