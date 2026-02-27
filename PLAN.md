# TextMate Modernization Plan

## Context

TextMate (exmate) has been modernized to target macOS 13.0 (Ventura). The codebase has been updated to remove deprecated APIs, vendor dependencies, and ensure a clean build with **zero warnings**.

**Build Status:** ✅ Zero warnings, zero errors

**Key decisions made:**
- Minimum OS: macOS 13.0 (Ventura)
- Static libraries: Keep all 48 internal frameworks as static `.a` files (LTO + dead stripping is optimal for a single-binary app)
- Execution order: Keep PRs in their current listed order and keep overlap-alert steps separate (no PR merges)
- Fork workflow: When a submodule fork is required, stop and wait for the user to create the fork before continuing
- Dependency versioning: For PR 5 (Cap'n Proto) and PR 6 (Onigmo), select the exact tag at implementation time (latest stable at that time) and record it in the PR notes

---

## Completed: PRs 1-11

All PRs 1-11 are complete. The build succeeds with **zero warnings** (except for documented suppressions).

### PR 1: Raise deployment target to macOS 13.0 and remove SDK compat shims ✅
- Changed minimum deployment target from 10.12 to 13.0
- Removed `sdk-compat.h` and all related code

### PR 2: Modernize oak/compat.h ✅
- Replaced Gestalt-based OS version detection with `NSProcessInfo.operatingSystemVersion`
- Simplified `oak::vfork()` wrapper

### PR 3: Fix Ruby build scripts for Ruby 2.6+ compatibility ✅
- Fixed `File.exists?` → `File.exist?` in Ruby scripts
- Updated bundle command templates

### PR 4: Add Ruby version management support ✅
- Added `TM_RUBY` shell variable documentation
- Added help section for Ruby version management

### PR 5: Add Cap'n Proto as a vendored submodule ✅
- Replaced Homebrew-linked `libcapnp` and `libkj` with vendored Git submodule

### PR 6: Update Onigmo submodule to latest version ✅
- Updated Onigmo regex library to latest release

### PR 7: Update configure script for modern Homebrew ✅
- Modernized configure for Apple Silicon vs Intel paths
- Removed capnp library checks

### PR 8: Migrate vfork callers to posix_spawn ✅
- Replaced all `oak::vfork()` + `execve()` patterns with `posix_spawn()`

### PR 9: Replace deprecated type identifier and icon APIs with UniformTypeIdentifiers ✅
- Replaced `NSFileTypeForHFSTypeCode`, `GetIconRef`/`ReleaseIconRef` with `UTType`

### PR 10: Migrate legacy WebView to WKWebView in HTMLOutput ✅
- Replaced deprecated `WebView` with `WKWebView` in HTML output subsystem
- Updated JavaScript bridge to use `WKScriptMessageHandler`

### PR 11: Address remaining deprecation warnings ✅
- 11a-11o: All remaining deprecation warnings addressed
- Fixed missing NSConnection pragma suppression in `commit.mm`
- Fixed unused variable `rc` in `PrivilegedTool/main.cc`
- Fixed unused variable bug in `Favorites.mm` (was using `item.link` instead of `link`)
- Build now has **zero warnings**

---

## Remaining Work: PRs 12-15

### PR 12: Fix interface layout metrics and backgrounds for macOS 13

**What:** Update the app's UI to macOS 13's design language. Adjust NSVisualEffectView materials, tab bar metrics, and sidebar vibrancy. Investigate native window tabs.

**Why:** When compiled against the macOS 13 SDK, macOS applies different default metrics and vibrancy materials, producing windows with incorrect backgrounds and layout.

**Decisions:**
- **Sidebar**: Keep existing `ProjectLayoutView` (custom constraint layout), adjust NSVisualEffectView materials only. TODO for future NSSplitViewController migration.
- **XIB notices**: Don't fix now (68 pre-existing notices across 9 XIBs). Re-check after UI model changes.
- **Tab bar**: Investigate native `NSWindow.tabbingMode`. If impractical, adjust custom `OakTabBarView`.
- **Preferences window**: Already uses `NSWindowToolbarStylePreference` — no changes needed.
- **Document window**: Does NOT use NSToolbar — uses custom tab bar via `NSTitlebarAccessoryViewController`. No toolbar style changes needed.

**Implementation Steps:**

**Step 1: Investigate native window tabs**
- Temporarily set `tabbingMode = NSWindowTabbingModePreferred` in `DocumentWindowController.mm:200`
- Expected: incompatible with single-window multi-document model (requires one-window-per-document)
- Deliverable: revert test, add TODO comment in `OakTabBarView.mm`

**Step 2: Update NSVisualEffectView materials**
- Change `NSVisualEffectMaterialTitlebar` → `NSVisualEffectMaterialHeaderView` in:
  - `HOStatusBar.mm:45`, `OTVStatusBar.mm:75`, `OFBHeaderView.mm:36`, `OFBActionsView.mm:22`

**Step 3: Add sidebar vibrancy**
- Add `NSVisualEffectView` with `NSVisualEffectMaterialSidebar` as background in `FileBrowserView.mm`
- Fallback: if conflicts with header/actions views, back out

**Step 4: Update tab bar metrics**
- Adjust `OakTabBarView.mm`: intrinsic height 23→28pt, internal padding adjustments

**Step 5: Update tab bar drawing colors**
- Replace hardcoded `colorWithCalibratedWhite:NSBlack alpha:0.25` borders → `NSColor.separatorColor`

**Step 6: Verify window chrome and dividers** (read-only)

**Step 7: Adjust status bar heights if needed** (visual judgment)

**Step 8: Re-check XIB notices** after all changes

**Step 9: Add TODO comments** for future NSSplitViewController and native tab migrations

**Files modified:**

| File | Steps |
|------|-------|
| `Frameworks/OakTabBarView/src/OakTabBarView.mm` | 1, 4, 5, 9 |
| `Frameworks/HTMLOutput/src/browser/HOStatusBar.mm` | 2, 7 |
| `Frameworks/OakTextView/src/OTVStatusBar.mm` | 2, 7 |
| `Frameworks/FileBrowser/src/OFB/OFBHeaderView.mm` | 2, 7 |
| `Frameworks/FileBrowser/src/OFB/OFBActionsView.mm` | 2, 7 |
| `Frameworks/FileBrowser/src/FileBrowserView.mm` | 3, 9 |
| `Frameworks/DocumentWindow/src/DocumentWindowController.mm` | 1 (temp) |
| `Frameworks/DocumentWindow/src/ProjectLayoutView.mm` | 9 |

**Validation:** Visual comparison after each step: `ninja TextMate/run`. Test file browser, multiple tabs, HTML output, status bar, light/dark mode, active/inactive, full-screen.

---

### PR 13: Xcode build integration

**What:** Modify `./configure` so it creates a `project.yml` with the appropriat targets mapped, and then calls `xcodegen` to create (or overwrite) an Xcode project. This Xcode project should have targets for each of the major deliverable artifacts (see below), and building should execute the underlying ninja flows so as to create the same product that you'd get by running ninja from the command line.

**Implementation:* Extend `./configure` so that it creates a `project.yml` for use with the installed Xcode version, and to then call `xcodegen` to produce or update the Xcode project. The Xcode project should have targets for all the top-level targets from the ninja.build file (targets that aren't varianted with a /...), and the variant targets (/run, /debug, /debug/run) then expressed in the run schemes for the top-level targets. A user can then use Xcode to build-and-run, debug, or inspect the application, as well as apply Xcode's own development functionality with the existing source.

**Files to create/modify:**
- **`bin/gen_xcodeproj`** (new script) — detect Xcode version, run xcodegen
- **`configure`** — add call to `bin/gen_xcodeproj`
- **`build/include/` symlinks** — verify symlinks are created

**Run scheme mapping:*

`ninja -c targets` shows a number of targets, most of which include a primary target (e.g. "TextMate") and a number of variant targets (e.g. "TextMate/debug", "TextMate/debug/run", "TextMate/run"). All the non-variant ninja targets should become targets in Xcode. Those Xcode targets' run schemes should then be adjusted so they work with the output of the appropriate variant scheme.

| Xcode run scheme | ninja target |
| Build            | primary or /debug, depending on calling scheme |
| Run              | /debug/run                                     |
| Test             | /debug/run                                     |
| Profile          | /run                                           |
| Analyze          | /debug                                         |
| Archive          | primary                                        |

**Validation:**
1. `./configure` succeeds and produces both `build.ninja` and `TextMate.xcodeproj`
2. `xcodebuild build -scheme TextMate -configuration Debug` succeeds
3. The built `TextMate.app` launches and is functional

---

### PR 14: Add test infrastructure and CI

**What:** Add comprehensive tests for modernized APIs, and a GitHub Actions CI workflow.

**New tests:**
- OS version detection test (verify `oak::os_major() >= 13`)
- posix_spawn process tests (fd handling, process groups, working directory)
- UTType icon resolution tests
- WKWebView integration tests (URL scheme handler, JS bridge message passing)
- Layout constraint satisfaction tests (no ambiguous layout)
- Dark mode toggle smoke test

**CI workflow** (`.github/workflows/build.yml`):
```yaml
name: Build
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - run: brew install xcodegen ragel multimarkdown capnp boost google-sparsehash
      - run: ./configure
      - run: ninja
```

**Validation:** `ninja` passes all existing + new tests. CI workflow succeeds.

---

### PR 15: Documentation and final cleanup

**What:** Update README, remove dead code, clean up stale `#pragma` suppressions.

**Files:**
- `README.md` — update build requirements (macOS 13.0+, Xcode 14.0+, vendored capnp, Homebrew tools)
- Remove any remaining `#pragma` that are no longer needed
- Add Ruby version management documentation

**Validation:** Fresh clone → `git submodule update --init --recursive` → `./configure` → `ninja` — all green.

---

## Documented Suppressions

The build has **zero warnings**. The following deprecated APIs are used but suppressed with `#pragma` or build flags. Each has a `// TODO:` comment explaining what would be required to migrate to modern APIs.

### A. Suppressions Added by This Modernization

| Suppressed API | Files | Why | Migration Effort |
|---------------|-------|-----|------------------|
| SecTransform (DSA) | 2 | TextMate's update signing keys are DSA-1024/2048; SecKeyVerifySignature doesn't support DSA | Medium (needs key rotation) |
| NSConnection (DO) | 5 | Foundational IPC for dialog plugins and CommitWindow; no drop-in replacement | Large (XPC rewrite) |
| QuickLook Generator | 1 | Legacy QLGenerator plugin model → requires extension architecture rewrite | Large |

### B. Pre-existing Suppressions

| Suppressed API | Files | Why |
|---------------|-------|-----|
| AuthorizationExecuteWithPrivileges | 1 | Needs SMJobBless or XPC service redesign |
| FSRef / Carbon Resource Manager | 1 | Reading resource forks for `.textClipping` files |

### C. Vendor Build-Flag Suppressions

| File | Flag | Reason |
|------|------|--------|
| `vendor/kvdb/default.rave` | `-Wno-deprecated-declarations` | Third-party SQLite-backed KV store |
| `vendor/capnp/default.rave` | `-Wno-deprecated-this-capture` | Cap'n Proto upstream fix pending |

---

## Commit Dependency Graph

```
PR 1 (deployment target + remove sdk-compat.h)
├── PR 2 (modernize compat.h)          [depends on 1]
│   ├── PR 8 (posix_spawn migration)   [depends on 2]
│   └── PR 11 (remaining deprecations) [depends on 2, 9, 10]
├── PR 9 (UTType icons)                [depends on 1]
├── PR 10 (WKWebView migration)       [depends on 1]
├── PR 12 (layout metrics)            [depends on 1, 10]
│
├── PR 3 (Ruby build scripts)         [independent]
├── PR 4 (Ruby version management)    [depends on 3]
├── PR 5 (vendor capnp)               [independent]
├── PR 6 (update Onigmo)              [independent]
└── PR 7 (configure modernization)    [depends on 5]

PR 13 (Xcode build integration)        [last]
PR 14 (tests + CI)                     [depends on 8, 9, 10]
PR 15 (docs + cleanup)                [depends on all]
```

---

## Risk Summary

| PR | Risk | Notes |
|----|------|-------|
| 1-2 | Low | Mechanical changes |
| 3-4 | Low | Ruby script fixes are straightforward |
| 5 | Medium | Cap'n Proto C++ source integration |
| 6 | Medium | Regex behavior changes possible |
| 7 | Low | Simple script updates |
| 8 | Medium | Subtle fd handling differences |
| 9 | Low-Medium | UTType APIs well-documented |
| 10 | **High** | JS bridge rearchitecture |
| 11 | Low | Sweep pass, individual items small |
| 12 | Medium | Requires visual testing, UI framework changes |
| 13 | Low | Script creation |
| 14 | Low | Testing and documentation |
| 15 | Low | Documentation updates |

---

## Still To Do

- Migrate off AuthorizationExecuteWithPrivileges
- Switch to GitHub tracking of plugins
