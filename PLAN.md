# TextMate Modernization Plan

## Context

TextMate (exmate) currently targets macOS 10.12 (Sierra) and uses several deprecated APIs, a Homebrew-linked Cap'n Proto, an old Onigmo 5.13.5, and an SDK compatibility shim. The goal is to modernize the codebase to target macOS 13.0 (Ventura), vendor dependencies properly, address all deprecation warnings with real API migrations, and ensure the app builds, runs, and passes tests after each step for PRs 1-13 and 15. PR 14 (Xcode build integration) comes last to generate the Xcode project for final validation. After each step, the build should work as well or better than it did in the prior step, and testing should confirm that.

**Key decisions made:**
- Minimum OS: macOS 13.0 (Ventura)
- Static libraries: Keep all 48 internal frameworks as static `.a` files (LTO + dead stripping is optimal for a single-binary app)
- Execution order: Keep PRs in their current listed order and keep overlap-alert steps separate (no PR merges)
- Fork workflow: When a submodule fork is required, stop and wait for the user to create the fork before continuing
- Dependency versioning: For PR 5 (Cap'n Proto) and PR 6 (Onigmo), select the exact tag at implementation time (latest stable at that time) and record it in the PR notes

---

## Submodule Forking Policy

Several submodules are hosted in the `textmate` GitHub org. If any PR requires modifying code *within* a submodule (not just bumping its commit pointer from the parent repo), the work must be done in a fork under the user's GitHub account (`faisal`), named `extmate-[original-repo-name]`, on a branch named `sdk_update_three` (matching this repo's branch).

**Submodules hosted at textmate/* (from `.gitmodules`):**

| Submodule path | Upstream repo | Fork needed? | Fork repo name |
|---|---|---|---|
| `bin/CxxTest` | `textmate/cxxtest` | No — no code changes planned | — |
| `Applications/TextMate/icons` | `textmate/document-icons` | No — no code changes planned | — |
| `PlugIns/dialog` | `textmate/dialog` | **Yes** — PR 10 modifies `TMDHTMLTips.mm` (WKWebView tooltip migration) | `faisal/extmate-dialog` |
| `PlugIns/dialog-1.x` | `textmate/dialog-1.x` | Possibly — review during PR 10 | `faisal/extmate-dialog-1.x` |
| `vendor/Onigmo/vendor` | `textmate/Onigmo` | Possibly — only if custom patches are needed for the Onigmo update (PR 6). If we just bump to a new upstream tag, no fork needed. | `faisal/extmate-Onigmo` |
| `vendor/kvdb/vendor` | `textmate/kvdb` | No — no code changes planned | — |

**Existing forks with different names:** Some submodules already have `faisal` remotes with older naming (`faisal/dialog.git`, `faisal/dialog-1.x.git`, `faisal/kvdb.git`). The new convention uses `extmate-*` names. When a fork is needed, I will stop and provide instructions for creating it on GitHub before proceeding.

**When a fork is created:** `.gitmodules` in the parent repo will be updated to point to the `extmate-*` fork URL so that `git submodule update --init --recursive` works for collaborators. The submodule will track the `sdk_update_three` branch.

---

## PR 14: Xcode build integration — configure generates the Xcode project

**What:** Extend `./configure` so that it updates `project.yml` to reflect the installed Xcode version, then runs `xcodegen` to generate `TextMate.xcodeproj`. Ensure all build-phase scripts work whether invoked from ninja or from Xcode.

**Why:** The Xcode project must be a first-class build path, not a stale artifact. This PR generates the Xcode project for final validation. Currently `project.yml` has `xcodeVersion: "26.0"` but the installed Xcode may differ — this should be auto-detected. Most targets in `project.yml` use directory-level source paths (xcodegen auto-discovers files), but vendor targets (Onigmo, kvdb) use explicit file lists that can drift.

**Files to create/modify:**

- **`bin/gen_xcodeproj`** (new script) — a shell script that:
  1. Checks that `xcodegen` is installed; exits with install instructions if not (`brew install xcodegen`)
  2. Detects the installed Xcode version via `xcodebuild -version` and updates the `xcodeVersion:` field in `project.yml` (using `sed` or similar)
  3. For vendor targets with explicit file lists (Onigmo, kvdb), validates that listed source files exist on disk and warns about any mismatches (new files on disk not in project.yml, or listed files missing from disk)
  4. Runs `xcodegen generate` to produce/update `TextMate.xcodeproj`

- **`configure`** — add a call to `bin/gen_xcodeproj` after the existing rave invocation, so `./configure` now produces both ninja build files and the Xcode project. If `xcodegen` is absent, warn but do not fail (the ninja build path still works without it).

- **`build/include/` symlinks** — verify these symlinks (e.g., `build/include/text → ../../Frameworks/text/src`) are created by configure or gen_xcodeproj. The Xcode build's `HEADER_SEARCH_PATHS` includes `$(SRCROOT)/build/include` and depends on them. If they aren't created, add a step to gen_xcodeproj to create them.

- **Build phase script audit** — confirm all `preBuildScripts` and build rules in `project.yml` use portable environment variables (`${SRCROOT}`, `${DERIVED_FILE_DIR}`, `${SCRIPT_INPUT_FILE}`) and invoke tools by name (not absolute path). Current scripts:
  - Cap'n Proto code generation (encoding, plist) — uses `${SRCROOT}`, `${DERIVED_FILE_DIR}` ✓
  - Version extraction from Changes.md — uses `${SRCROOT}` ✓
  - Markdown→HTML via `multimarkdown` — requires `multimarkdown` in PATH ✓
  - Ragel build rules — requires `ragel` in PATH ✓
  - `bin/gen_xctest` test wrappers — uses `${SRCROOT}`, `${DERIVED_FILE_DIR}` ✓

**Implementation notes (in progress):**
- `bin/gen_xcodeproj` created; `bin/gen_xctest` created and rewritten (removed namespace wrapping that polluted transitive includes)
- `configure` updated to call `bin/gen_xcodeproj`
- `project.yml` updated: added `export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"` to capnp, ragel, and multimarkdown build scripts
- `Frameworks/scope/src/scope.h` fixed: `std::hash<scope::scope_t>` specialization wrapped in `namespace std { }`
- `Shared/include/test/OakTestMacros.h` updated: added `#include <oak/iterator_macros.h>` for `foreach` macro
- `capnp` installed via Homebrew (build-time compiler dependency)
- Main build succeeds; test compilation has remaining issues (e.g., `t_tokenize.cc` missing `#include <text/format.h>`)

**Validation:**
1. `./configure` succeeds and produces both `build.ninja` and `TextMate.xcodeproj`
2. `xcodebuild build -scheme TextMate -configuration Debug` succeeds
3. `xcodebuild test -scheme TextMate -configuration Debug` runs; pre-existing failing tests may remain for now and will be addressed in later planned steps (especially PR 13)
4. The built `TextMate.app` launches and is functional (open a file, basic editing)
5. Modify a source file, rebuild from Xcode — the change is picked up

---

## PR 1: Raise deployment target to macOS 13.0 and remove SDK compat shims

**What:** Change the minimum deployment target from 10.12 to 13.0 across all build configurations. Remove `sdk-compat.h` which provides forward declarations for APIs that are now standard (10.13+ NSAppearanceName, 10.14+ dark mode APIs, 11.0+ NSWindowToolbarStyle).

**Why:** macOS 13 (Ventura) covers the vast majority of active Mac users and provides all the modern APIs we need. All APIs we need (UniformTypeIdentifiers, WKWebView improvements, posix_spawn_file_actions_addchdir_np, NSProcessInfo.operatingSystemVersion) are available since macOS 10.15-11.0, so macOS 13 gives us full access with no `@available` guards needed.

**Files to modify:**
- `default.rave:1` — `APP_MIN_OS "10.12"` → `"13.0"`
- `xcconfigs/Shared.xcconfig:4` — `MACOSX_DEPLOYMENT_TARGET = 10.12` → `13.0`
- `project.yml:5,12` — both `"10.12"` → `"13.0"`
- `Shared/include/oak/sdk-compat.h` — delete file entirely
- Remove all `#include <oak/sdk-compat.h>` / `#import <oak/sdk-compat.h>` from prelude headers and any direct includers
- Remove `@available(macOS 10.14, *)` and `@available(macOS 11.0, *)` guards that are now always-true (search across Frameworks/)

**Validation:** `ninja -C build/release` succeeds. Expect new deprecation warnings (addressed in later PRs). Verify Info.plist LSMinimumSystemVersion resolves to 13.0.

---

## PR 2: Modernize oak/compat.h — replace Gestalt, simplify vfork wrapper

**What:** Replace deprecated Gestalt-based OS version detection with `NSProcessInfo.operatingSystemVersion`. Simplify the `oak::vfork()` wrapper to just call `fork()` (vfork is identical to fork on macOS 12+, and our minimum is now 13). Keep `AuthorizationExecuteWithPrivileges` wrapper with a documented note about future XPC migration.

**Why:** Gestalt was deprecated in macOS 10.8 and may be removed. The version-checking runtime logic in `oak::vfork()` is dead code since our minimum OS is 13.

**Files to modify:**
- `Shared/include/oak/compat.h` — rewrite:
  - `oak::os_major/os_minor/os_patch` → use `NSProcessInfo.processInfo.operatingSystemVersion`
  - `oak::vfork()` → just `return fork();` (remove runtime version check)
  - `oak::execute_with_privileges()` → keep but add `#warning` noting future migration to XPC service
- Verify callers compile: `Frameworks/file/src/path_info.mm`, `Frameworks/network/src/user_agent.mm` (both already .mm so Obj-C APIs work)
- Verify `Frameworks/crash/src/info.cc` which uses `oak::os_major()` — may need conversion to .mm or a non-ObjC fallback

**Validation:** Build succeeds. Run app, verify About window shows correct OS version string.

---

## PR 3: Fix Ruby build scripts for Ruby 2.6+ compatibility

**What:** Update all Ruby scripts in the build system to work with system Ruby 2.6 (shipped with macOS 11-14). Fix deprecated Ruby patterns.

**Why:** The build system (`bin/rave`, `bin/gen_credits.rb`, `configure`) uses Ruby. System Ruby 2.6 is available on macOS 13. Scripts must not depend on newer Ruby or gems.

**Files to modify:**
- `bin/rave` — `File.exists?` → `File.exist?` (deprecated since Ruby 2.1, removed in 3.2)
- `bin/gen_credits.rb` — audit for Ruby 1.8-isms, fix `File.exists?` if present
- `Frameworks/CrashReporter/bin/symbolicate` — audit
- `configure` — ensure `#!/bin/sh` scripts don't accidentally depend on Ruby version
- Clear `GEM_HOME`/`GEM_PATH` environment in rave invocations to avoid gem conflicts (as sonnet_all branch did)

**Also update bundle command templates:**
- `Frameworks/BundleEditor/templates/Command.plist` — `ruby18` → `ruby` in shebang
- `Frameworks/BundleEditor/templates/Drag Command.plist` — same
- `Applications/TextMate/support/Bundles/Avian.tmbundle/Commands/*.tmCommand` — `ruby18` → `ruby`

**Validation:** `./configure` runs cleanly. `bin/rave -crelease -tTextMate` generates build files. Full build succeeds.

---

## PR 4: Add Ruby version management support for user projects

**What:** Add documentation and settings support for users who manage Ruby via chruby, rbenv, ruby-install, Homebrew, or other tools.

**Why:** TextMate bundle commands execute via shebangs (e.g., `#!/usr/bin/env ruby`). Users need their preferred Ruby version to be used, not necessarily the system Ruby.

**Approach:**
- Document the `TM_RUBY` shell variable in `Default.tmProperties` — users can set this per-project or globally to point to their preferred Ruby
- Update `Applications/TextMate/resources/Default.tmProperties` to document `TM_RUBY` usage:
  ```
  [ source.ruby ]
  TM_RUBY = "/usr/bin/ruby"
  ```
- Add a help section in `Applications/TextMate/resources/TextMate Help/` explaining:
  - Default: `/usr/bin/ruby` (system Ruby 2.6)
  - chruby users: set `TM_RUBY` to `~/.rubies/<version>/bin/ruby`
  - rbenv users: set `TM_RUBY` to `~/.rbenv/shims/ruby` (or use rbenv's PATH)
  - Homebrew Ruby: set `TM_RUBY` to `/opt/homebrew/opt/ruby/bin/ruby`
  - Per-project: add `.tm_properties` with project-specific `TM_RUBY`
- Ensure the command execution PATH in `Frameworks/command/src/runner.mm` respects shell init files or at minimum `~/.tm_properties` variables

**Validation:** Set TM_RUBY to a specific Ruby, run a Ruby bundle command, verify it uses the configured Ruby.

---

## PR 5: Add Cap'n Proto as a vendored submodule

**What:** Replace the Homebrew-linked `libcapnp` and `libkj` with a vendored Git submodule built from source, compiled to match the deployment target.

**Why:** Homebrew capnp may be built for a different deployment target. Vendoring ensures the library matches our macOS 13 minimum and removes a runtime dependency. The `capnp` compiler binary remains a Homebrew build-time dependency (like `ragel` and `multimarkdown`).

**Files to create/modify:**
- `.gitmodules` — add `vendor/capnp/vendor` pointing to `https://github.com/capnproto/capnproto.git` (pin to latest stable tag)
- `vendor/capnp/` — new directory with build integration
- `project.yml` — add two new static library targets:
  - `kj` — builds `libkj.a` from `vendor/capnp/vendor/c++/src/kj/*.c++` (excluding tests)
  - `capnp_lib` — builds `libcapnp.a` from `vendor/capnp/vendor/c++/src/capnp/*.c++` (excluding tests and compiler)
- `xcconfigs/Vendor-capnp.xcconfig` — new file with capnp-specific settings (header paths, suppress warnings in vendor code, C++20 standard)
- `xcconfigs/Shared.xcconfig` — remove `-lcapnp -lkj` from `OTHER_LDFLAGS`
- `project.yml` encoding/plist targets — add dependencies on `kj`/`capnp_lib`, remove `-lcapnp -lkj` from their `OTHER_LDFLAGS`
- `configure` — remove library checks for capnp/kj (keep compiler binary check)
- `local.rave` / Shared.xcconfig — keep `/opt/homebrew/include` for boost/sparsehash, keep `/opt/homebrew/lib` only if still needed

**Note:** Cap'n Proto's C++ source is self-contained but has many files. The Xcode target needs careful source file selection. I'll review the capnp CMakeLists.txt to identify exactly which `.c++` files to include for the runtime libraries (not the compiler, schema loader, or RPC layer unless needed). The exact upstream tag will be chosen at implementation time (latest stable then) and documented in the PR.

**Validation:** Build succeeds without Homebrew capnp libraries installed (only the `capnp` compiler binary needed). `encodingTests` and `plistTests` pass.

---

## PR 6: Update Onigmo submodule to latest version

**What:** Update the Onigmo regex library from version 5.13.5 to the latest release.

**Why:** Bug fixes, performance improvements, and Unicode updates since 5.13.5. The current version is based on Oniguruma 5.9.6 with Ruby patches from ~2015.

**Submodule fork checkpoint:** Before starting this PR, assess whether a fork is needed. If only bumping the submodule pointer to a new upstream tag — no fork needed. If custom patches are required for TextMate compatibility — stop, provide instructions for creating `faisal/extmate-Onigmo` on GitHub, and wait for user confirmation that the fork exists before proceeding.

**Files to modify:**
- `vendor/Onigmo/vendor` — update submodule to latest tag
- `vendor/Onigmo/config.h` — regenerate for new version (update PACKAGE_VERSION, PACKAGE_STRING)
- `vendor/Onigmo/src/setup.c` — review if still compatible with new version
- `project.yml` Onigmo target — update source file list if new version adds/removes files in `enc/`
- `Frameworks/regexp/src/` — verify API compatibility. Grep for `onig_` function calls and check they still exist

**Risk:** Regex behavior changes could subtly affect syntax highlighting. Thorough testing of the regexp framework is essential.

**Tag selection policy:** Choose the exact Onigmo tag at implementation time (latest stable at that time) and record the chosen tag in the PR notes.

**Validation:** Build `Onigmo` target. Run `OnigmoTests` and `regexpTests`. Open diverse source files and verify syntax highlighting is correct.

---

## PR 7: Update configure script for modern Homebrew and cleaned-up dependencies

**What:** Modernize the `configure` script to properly detect Apple Silicon vs Intel Homebrew paths, remove checks for now-vendored capnp libraries, and ensure `local.rave` is generated correctly.

**Why:** The configure script currently hardcodes paths that may not work on Apple Silicon (`/usr/local` vs `/opt/homebrew`). With capnp vendored, the library checks are unnecessary.

**Files to modify:**
- `configure` — use `$(brew --prefix)` consistently, remove capnp/kj library checks, keep boost/sparsehash header checks and capnp/ragel/multimarkdown/ninja binary checks
- `local.rave` — regenerate

**Validation:** Delete `local.rave`, run `./configure`, verify correct regeneration. Full build succeeds.

---

## PR 8: Migrate vfork callers to posix_spawn

**What:** Replace all `oak::vfork()` + `execve()` patterns with `posix_spawn()`, following the existing reference implementation in `Frameworks/io/src/exec.cc`.

**Why:** vfork is deprecated since macOS 12. The codebase already has a proper posix_spawn implementation in `io::spawn()`. Migrating the remaining callers eliminates the last deprecated process creation API usage.

**Files to modify:**
- `Frameworks/command/src/runner.mm` — rewrite `my_fork()` (lines 17-81) to use `posix_spawn_file_actions` for fd redirection, `posix_spawnattr_setpgroup` for process group, `posix_spawn_file_actions_addchdir_np` for working directory
- `Frameworks/OakCommand/src/OakCommand.mm` — same `my_fork()` pattern migration
- `Frameworks/OakDebug/src/OakAssert.mm` — rewrite `OakStackDump()` to use `posix_spawn` or the existing `io::spawn()`
- `Applications/mate/src/mate.mm` — replace `oak::vfork()` + `execve()` at line 92 with `posix_spawn`
- `Applications/PrivilegedTool/src/install.mm` — replace `oak::vfork()` + `execve()` at line 47 with `posix_spawn`
- `Shared/include/oak/compat.h` — remove `oak::vfork()` wrapper entirely (no callers remain)

**Validation:** Run a bundle command (tests runner.mm). Force a debug assertion (tests OakAssert.mm). Run `commandTests`. Verify process cleanup works correctly (no zombie processes).

---

## PR 9: Replace deprecated type identifier and icon APIs with UniformTypeIdentifiers

**What:** Replace `NSFileTypeForHFSTypeCode`, `GetIconRef`/`ReleaseIconRef`, and legacy UTI string-based APIs with the `UniformTypeIdentifiers` framework (`UTType`).

**Why:** These Carbon-era APIs are deprecated and will eventually be removed. UniformTypeIdentifiers (macOS 11+) is the modern replacement.

**Files to modify:**
- `Frameworks/TMFileReference/src/TMFileReference.mm` — replace `NSFileTypeForHFSTypeCode(kUnknownFSObjectIcon)` etc. with `UTTypeItem`/`UTTypeFolder`/`UTTypeContent` via `[NSWorkspace.sharedWorkspace iconForContentType:]`. Replace `GetIconRef`/`ReleaseIconRef` for alias badge with SF Symbols or a bundled asset.
- `Frameworks/OakTabBarView/src/OakTabBarView.mm` — migrate type identifier usage
- `Frameworks/OakAppKit/src/NSMenuItem Additions.mm` — same
- `Frameworks/FileBrowser/src/FileBrowserViewController.mm` — same
- `Frameworks/FileBrowser/src/FileItemImage.mm` — same
- `Frameworks/BundleEditor/src/` — any type identifier usage
- `Frameworks/Preferences/src/` — any type identifier usage
- Add `#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>` to affected files
- `project.yml` — add `-framework UniformTypeIdentifiers` to OTHER_LDFLAGS for affected targets
- Some `.cc` files may need conversion to `.mm` to use Obj-C UniformTypeIdentifiers API

**Reference:** The `sonnet_all` branch (`remotes/exmate/sonnet_all`) — an earlier, abandoned attempt at the same modernization goals — has partial UTType migrations for these files. Use as directional guidance only; it was done under different assumptions and is incomplete.

**Validation:** Build. Open file browser, verify correct icons for files, folders, symlinks. Create new documents, verify correct type associations. Run `OakAppKitTests`, `FileBrowserTests`.

---

## PR 10: Migrate legacy WebView to WKWebView in HTMLOutput

**What:** Replace all usage of the deprecated `WebView` class with `WKWebView` in the HTML output subsystem and Dialog tooltip plugin. This is the largest single change.

**Why:** `WebView` (WebKit legacy) was deprecated in macOS 10.14. `WKWebView` is the modern replacement with better security, performance, and process isolation.

**Submodule fork checkpoint:** Before starting this PR, stop and provide instructions for creating the `faisal/extmate-dialog` repo on GitHub (fork of `textmate/dialog`), then wait for user confirmation before continuing. The `TMDHTMLTips.mm` file in `PlugIns/dialog/` needs WKWebView migration. Work will be done on the `sdk_update_three` branch in that fork, and `.gitmodules` will be updated to point to it.

**Scope (10 files with direct WebView references, plus helper files that may need new WKWebView glue):**
- `Frameworks/HTMLOutput/src/browser/HOBrowserView.{h,mm}` — core browser view
- `Frameworks/HTMLOutput/src/browser/HOWebViewDelegateHelper.{h,mm}` — delegate helper
- `Frameworks/HTMLOutput/src/OakHTMLOutputView.mm` — main output view (`.h` has no current WebView refs but may gain WKWebView property declarations)
- `Frameworks/HTMLOutput/src/helpers/HOJSBridge.{h,mm}` — JavaScript bridge (no current WebView refs; will need new WKScriptMessageHandler glue)
- `Frameworks/HTMLOutput/src/helpers/HOAutoScroll.{h,mm}` — auto-scroll (no current WebView refs; will need adaptation for WKWebView scroll API)
- `Frameworks/HTMLOutput/src/helpers/WebView Additions.mm` — category (delete)
- `Frameworks/OakCommand/src/OakCommand.mm` — custom URL scheme registration
- `PlugIns/dialog/Commands/tooltip/TMDHTMLTips.mm` — tooltip rendering (**in dialog submodule fork**)
- `Frameworks/DocumentWindow/src/DocumentWindowController.mm` — webView property refs

**Key architectural changes:**
| Legacy | Modern |
|---|---|
| `WebView` | `WKWebView` |
| `WebPolicyDelegate/WebUIDelegate/WebFrameLoadDelegate/WebResourceLoadDelegate` | `WKNavigationDelegate` + `WKUIDelegate` |
| `WebPreferences` | `WKWebViewConfiguration` + `WKPreferences` |
| `WebScriptObject` + `isSelectorExcludedFromWebScript:` | `WKScriptMessageHandler` + injected JS shim |
| `NSURLProtocol` custom schemes | `WKURLSchemeHandler` (setURLSchemeHandler:forURLScheme:) |
| `[frame loadHTMLString:]` | `[webView loadHTMLString:baseURL:]` |
| `mainFrame.stopLoading` | `[webView stopLoading]` |

**Reference:** `Applications/TextMate/src/AboutWindowController.mm` already uses WKWebView with WKScriptMessageHandler and injected JS — this is the pattern to follow.

**Risk:** Highest risk change. The JavaScript bridge (`TextMate.system()`, `TextMate.open()`, `TextMate.log()`) must work identically since all HTML-output bundle commands depend on it.

**Validation:** Run a bundle command with HTML output. Test `TextMate.system()` from JavaScript. Test navigation (back/forward). Test the Dialog2 tooltip. Test progress bar (estimatedProgress KVO). Test custom URL scheme (`x-txmt-filehandle`, `tm-file`).

---

## PR 11: Address remaining deprecation warnings

**What:** Audit and fix all remaining deprecation warnings. This is a sweep pass for anything not covered by PRs 2, 8, 9, 10.

**Why:** The user asked to address deprecation warnings with proper fixes rather than suppression.

**Known items to address:**
- `AuthorizationExecuteWithPrivileges` in `compat.h` / `authorization/src/server.mm` / `Preferences/src/TerminalPreferences.mm` — document the XPC migration path and keep minimal, focused suppression with `// TODO` explaining why (no drop-in replacement exists without SMJobBless) until a dedicated XPC/SMJobBless migration
- Any `Carbon.framework` deprecated APIs beyond what's already addressed
- Deprecated `NSWindow`/`NSView` methods if any remain
- Deprecated `ExceptionHandling.framework` usage in OakDebug
- Any pasteboard type deprecations (`NSStringPboardType` etc.)
- Search for all `#pragma clang diagnostic ignored "-Wdeprecated-declarations"` and evaluate each one

**For each warning, the approach is:**
1. If a modern API replacement exists → replace it
2. If no replacement exists (e.g., AuthorizationExecuteWithPrivileges) → document why, keep minimal suppression (accepted for now)
3. Present each proposed change and its rationale for review

**Validation:** `ninja -C build/release 2>&1 | grep -i deprecat` returns zero warnings (or only documented/accepted ones).

---

## PR 12: Fix interface layout metrics for macOS 13

**What:** Adjust UI metrics and layout code so the app's appearance matches the intended design from the macOS 10.12 era, accounting for system metric changes in macOS 13.

**Why:** When compiled against a newer SDK, macOS applies different default metrics (title bar height, toolbar spacing, control sizing, tab bar dimensions, vibrancy materials). The visual appearance should remain consistent with the original design.

**Files to examine and adjust:**
- `Frameworks/OakTabBarView/src/OakTabBarView.mm` — tab bar height and drawing metrics
- `Frameworks/FileBrowser/src/OFB/OFBHeaderView.mm` — file browser header
- `Frameworks/HTMLOutput/src/browser/HOStatusBar.mm` — status bar
- `Frameworks/OakTextView/src/OTVStatusBar.mm` — editor status bar
- `Frameworks/OakAppKit/src/OakUIConstructionFunctions.mm` — UI construction helpers
- `Frameworks/Preferences/src/Preferences.mm` — window toolbar style (already uses `NSWindowToolbarStylePreference`)
- `Frameworks/DocumentWindow/src/DocumentWindowController.mm` — main window chrome

**Approach:**
1. Build and run on macOS 13+ to identify visual discrepancies vs. design reference
2. For non-toolbar UI areas, use the app appearance from the macOS 10.12-SDK build as the intended baseline
3. Audit hardcoded metrics (pixel values, font sizes, padding)
4. Update `NSWindowToolbarStyle` settings if needed
5. Adjust `NSVisualEffectView` material choices for macOS 13 vibrancy
6. Fix any Auto Layout constraint conflicts that arise from changed intrinsic sizes
7. Test dark mode appearance

**Validation:** Visual comparison of running app vs. design reference. No ambiguous layout warnings. Dark mode toggle works without visual artifacts.

---

## PR 13: Add test infrastructure and CI

**What:** Add comprehensive tests for modernized APIs and a GitHub Actions CI workflow.

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
      - run: ninja -C build/release
```

**Validation:** `ninja -C build/release` passes all existing + new tests. CI workflow succeeds on push.

---

## PR 15: Documentation and final cleanup

**What:** Update README, remove dead code, clean up stale `#pragma` suppressions.

**Files:**
- `README.md` — update build requirements (macOS 13.0+, Xcode 14.0+, vendored capnp, Homebrew tools list including xcodegen)
- Remove any remaining `#pragma clang diagnostic ignored "-Wdeprecated-declarations"` that are no longer needed
- Remove stale `WebView Additions.mm` if not removed in PR 10
- Add Ruby version management documentation

**Validation:** Fresh clone → `git submodule update --init --recursive` → `./configure` → `ninja -C build/release` — all green.

---

## Commit Dependency Graph

```
PR 1 (deployment target + remove sdk-compat.h)
├── PR 2 (modernize compat.h)          [depends on 1]
│   ├── PR 8 (posix_spawn migration)   [depends on 2]
│   └── PR 11 (remaining deprecations) [depends on 2, 9, 10]
├── PR 9 (UTType icons)                [depends on 1]
├── PR 10 (WKWebView migration)        [depends on 1; SUBMODULE: dialog fork needed]
├── PR 12 (layout metrics)             [depends on 1, 10]
│
├── PR 3 (Ruby build scripts)          [independent]
├── PR 4 (Ruby version management)     [depends on 3]
├── PR 5 (vendor capnp)                [independent]
├── PR 6 (update Onigmo)               [independent; SUBMODULE: fork if patches needed]
└── PR 7 (configure modernization)     [depends on 5]

PR 13 (tests + CI)                     [depends on 8, 9, 10]
PR 14 (Xcode build integration)         [last — generates Xcode project for final validation]
PR 15 (docs + cleanup)                 [depends on all]
```

PR 1 comes first to modernize the deployment target. PRs 2-12 can proceed in parallel where dependencies allow. PR 14 (Xcode build integration) comes last to generate the Xcode project for final validation. The critical path remains: PR 1 → PR 2 → PR 8 / PR 10 → PR 13 → PR 14.

**Submodule fork checkpoints:** Before starting PR 10 (WKWebView), I will stop, provide instructions for creating the `faisal/extmate-dialog` fork on GitHub, and wait for your confirmation before continuing. Before PR 6 (Onigmo), I will assess whether a fork is needed or just a submodule pointer bump; if a fork is needed, I will stop and wait for your confirmation before continuing.

---

## Step Overlap Alerts

**Policy:** Overlap alerts are retained for context, and decisions are now fixed in this plan revision. Implementation should follow the recorded decisions unless explicitly changed later.

### Alert 1: PR 2 (compat.h) ↔ PR 8 (posix_spawn) — SUBSTANTIAL overlap

PR 2 simplifies `oak::vfork()` to just `return fork()`. PR 8 then replaces all vfork/fork+execve callers with `posix_spawn()` and deletes `oak::vfork()` entirely. Both PRs touch the same 6 files (`compat.h`, `runner.mm`, `OakCommand.mm`, `OakAssert.mm`, `mate.mm`, `install.mm`). Doing PR 2 as written creates an intermediate state that PR 8 immediately undoes.

**Options:**
- **(A) Merge PR 2 + PR 8 into one PR** — skip the intermediate `fork()` step, go straight to `posix_spawn`. Reduces rework and avoids touching the same files twice. The Gestalt→NSProcessInfo changes from PR 2 would be included in this combined PR.
- **(B) Keep separate** — PR 2 is a quick, safe change; PR 8 is riskier (fd handling). Separating them isolates risk and makes bisection easier.

**Decision:** **(B) Keep separate**.

### Alert 2: PR 10 (WKWebView) ↔ PR 12 (layout metrics) — MODERATE overlap

PR 10 rewrites 4+ HTMLOutput views (`HOBrowserView.mm`, `HOStatusBar.mm`, `OakHTMLOutputView.mm`, etc.) to replace WebView with WKWebView. PR 12 then adjusts layout metrics in those same views. If done separately, PR 12 will need to re-learn and re-edit the same code PR 10 just rewrote.

**Options:**
- **(A) Do layout metrics for HTMLOutput views as part of PR 10** — when rewriting each view for WKWebView, also set correct metrics. PR 12 then only covers non-HTMLOutput views (tab bar, file browser, preferences).
- **(B) Keep separate** — PR 10 focuses purely on API migration (WKWebView). PR 12 handles all layout as a dedicated visual polish pass. Cleaner separation of concerns but more file revisits.

**Decision:** **(B) Keep separate**.

### Alert 3: PR 5 (vendor capnp) ↔ PR 7 (configure modernization) — LOW-MODERATE overlap

PR 5 vendors capnp, which requires modifying `configure` to remove library checks and update `local.rave`. PR 7 modernizes `configure` more broadly (Homebrew path detection, cleanup). The `configure` script is ~60% capnp-related, so PR 5 will already do much of PR 7's work.

**Options:**
- **(A) Merge PR 5 + PR 7** — vendor capnp and modernize configure in one PR.
- **(B) Keep separate** — PR 5 does minimal configure changes (just remove capnp checks). PR 7 does the broader modernization pass. Lower risk per PR.

**Decision:** **(B) Keep separate**.

### Alert 4: PR 14 (Xcode build) ↔ PR 13 (test infrastructure)

PR 14 comes at the end to generate the Xcode project for final validation. PRs 1-13 validate using ninja build. This allows all modernization work to proceed before generating the Xcode project.

### Alert 5: PR 4 (Ruby version management) ↔ PR 8 (posix_spawn) — LOW overlap

PR 4 may modify PATH/environment handling in `Frameworks/command/src/runner.mm` to respect `TM_RUBY` and shell init files. PR 8 rewrites `my_fork()` in that same file to replace vfork+execve with posix_spawn. These are on independent dependency chains (PR 4 → PR 3; PR 8 → PR 2 → PR 1). If PR 4 lands first and PR 8 rewrites the function, PR 4's changes could be lost or need re-integration.

**Options:**
- **(A) Do PR 4 after PR 8** — ensures `runner.mm` is in its final posix_spawn form before adding Ruby PATH logic. Add a soft dependency edge: PR 4 should follow PR 8.
- **(B) Keep independent** — PR 4's changes are likely in a different part of `runner.mm` than `my_fork()`. Merge conflicts are manageable. Accept the risk.

**Decision:** **(B) Keep independent with current order**.

*Decisions above are fixed for this plan revision and should be followed as written during implementation.*

---

## Risk Summary

| PR | Risk | Notes |
|----|------|-------|
| 1-2 | Low | Mechanical changes; partially explored in abandoned `sonnet_all` branch |
| 3-4 | Low | Ruby script fixes are straightforward |
| 5 | Medium | Cap'n Proto C++ source integration needs careful file selection |
| 6 | Medium | Regex behavior changes could affect syntax highlighting; may need submodule fork |
| 7 | Low | Simple script updates |
| 8 | Medium | Subtle fd handling differences in posix_spawn vs vfork+execve |
| 9 | Low-Medium | UTType APIs are well-documented; abandoned `sonnet_all` branch has partial reference |
| 10 | **High** | Largest change; JS bridge rearchitecture; custom URL schemes; **requires dialog submodule fork** |
| 11 | Low | Sweep pass, individual items are small |
| 12 | Medium | Requires visual testing; metric changes can be subtle |
| 13 | Low | Testing and documentation |
| 14 | Low | Script creation; xcodegen is well-understood |
| 15 | Low | Documentation updates |
