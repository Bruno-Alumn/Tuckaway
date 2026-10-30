# Maintainer runbook

Build, verify, and release Tuckaway. Assumes current Xcode on macOS 13+.

## Build

```sh
# CI-style build, no signing required
xcodebuild -project 'Tuckaway.xcodeproj' -scheme 'Tuckaway' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

# runnable local build (uses your Apple Development identity)
xcodebuild -project 'Tuckaway.xcodeproj' -scheme 'Tuckaway' \
  -configuration Debug build
```

Both must exit 0 with **no** `MACOSX_DEPLOYMENT_TARGET` override; the floor is
13.0 in the project file. The single expected warning is the deliberately
deprecated `SMLoginItemSetEnabled(false)` call that cleans up legacy installs.

## Automated and behavioral verification

Run the complete suite:

```sh
xcodebuild -project 'Tuckaway.xcodeproj' -scheme 'Tuckaway' \
  -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO test
```

Also verify against the real menu bar:

1. **Truth signal**: the separator's AX size.
   `osascript -e 'tell application "System Events" to tell process "Tuckaway" to get size of menu bar item 2 of menu bar 2'`
   reads ~20pt expanded vs ~2x-screen-width collapsed. Item 1 is the arrow.
2. **Interaction**: `AXPress` supports accessibility toggling. Real `CGEvent`
   clicks can additionally exercise modifier handling and native event flow.

Standard checks before any release:

- expand/collapse toggle flips the separator size both ways;
- with `numberOfSecondForAutoHide` set to 3, an expanded bar survives 2x the
  window while the pointer is parked in the menubar band, collapses within the
  window once the pointer leaves, and collapses normally if the pointer never
  entered;
- `hoverToExpand` off: no monitor log line, hover does nothing; on: dwell
  expands (synthesize a `mouseMoved` stream: cursor warping alone fires no
  events);
- autostart pref on -> `AutoStart: SMAppService.mainApp.status = 1` on stderr;
  off -> `= 0` (run the binary directly to capture stderr);
- localization tables stay parseable: `plutil -lint hidden/*.lproj/*.strings`.

When testing on a machine that runs Tuckaway daily: export the prefs domain
first (`defaults export com.brunoalumn.tuckaway backup.plist`), quit the
installed app, test the dev build, then re-import and relaunch.

## Release

1. Verify the stack: every PR reviewed, builds green, behavioral checks above run.
2. Bump `MARKETING_VERSION` (all four Tuckaway configurations) and
   `CURRENT_PROJECT_VERSION` in the project file.
3. Archive the GitHub build with the **Tuckaway** scheme
   (`Release-Direct`), then notarize (Developer ID), staple, zip, and publish a
   GitHub release with notes listing closed issues. The **Tuckaway App Store**
   scheme archives `Release`, the sandboxed App Store build, which cannot hide
   on macOS 27. v1.11 shipped that build to GitHub by mistake. Before zipping,
   confirm the app is unsandboxed:

   ```sh
   codesign -d --entitlements - 'Tuckaway.app' | grep app-sandbox  # must print nothing
   ```

   The in-app updater installs this zip, so it must hold `Tuckaway.app` at the
   top level, its `CFBundleShortVersionString` must equal the release tag
   (`v1.1.0` ↔ `1.1.0`), and `codesign --verify --deep --strict` must pass.
   Also make sure it is a Release build: `Contents/MacOS` must not contain
   `Tuckaway.debug.dylib` (the v1.0.0 asset did).
4. App Store (separate lane, **Tuckaway App Store** scheme): the MAS listing
   has lagged GitHub since v1.8 (issues #281/#202); decide deliberately whether
   a release goes there too.
5. Homebrew cask (`brew install --cask hiddenbar`) follows the GitHub release
   artifact; notarization matters (issue #219).
6. Before any public release after the SMAppService migration: one
   upgrade-path run from a launcher-era build (v1.9 or older) verifying System
   Settings shows no ghost LauncherApplication login item.

## Stacked-PR hygiene

Feature stacks land as chained PRs (`develop <- A <- B`). Merge the base PR
first, then retarget the next PR's base to `develop` BEFORE merging it;
deleting a merged branch auto-closes dependents otherwise.

## Issue triage map

The live clusters and their code areas are documented at the end of
[ARCHITECTURE.md](ARCHITECTURE.md#known-architectural-limits): notch, macOS 27
mechanism break, and pointer-vs-open-menu limits. Memory reports (#361 et al.)
have so far not reproduced as leaks (constraint-leak fix landed; `leaks` clean
over toggle stress); re-check with a 24h+ uptime `footprint` sample before
chasing further.
