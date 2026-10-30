# Maintainer runbook

Build, verify, and release Tuckaway. Assumes current Xcode on macOS 13+.

## Build

```sh
# CI-style build, no signing required
xcodebuild -project 'Tuckaway.xcodeproj' -scheme 'Tuckaway' \
  -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO build

# runnable local build, ad-hoc signed (no Apple Developer account needed)
xcodebuild -project 'Tuckaway.xcodeproj' -scheme 'Tuckaway' \
  -configuration Debug-Direct CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

# the sandboxed App Store variant must keep compiling too
xcodebuild -project 'Tuckaway.xcodeproj' -scheme 'Tuckaway' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Use the `-Direct` configurations for anything you run on macOS 27. Plain
`Debug`/`Release` are the App Store variant: they can't hide on 27 and show the
"this version can't hide icons" notice on first launch.

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

1. **Truth signal (macOS 26 and earlier)**: the separator's AX size.
   `osascript -e 'tell application "System Events" to tell process "Tuckaway" to get size of menu bar item 2 of menu bar 2'`
   reads ~20pt expanded vs ~2x-screen-width collapsed. Item 1 is the arrow.
   On macOS 27 (direct build) there is no wide separator. Instead, collapse
   and confirm the hidden apps' icons disappear while the arrow and the
   visible ones remain.
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
- localization tables stay parseable: `plutil -lint hidden/*.lproj/*.strings`;
- Settings opens from the arrow's menu (⌘,), every General toggle sticks after
  reopening, and Menu Bar Items lists real items with Accessibility granted;
- the updater: from a build older than the latest release (or a Debug build
  with `TUCKAWAY_UPDATE_CURRENT_VERSION=0.9`), **Check for Updates…** offers
  the release and **Install and Relaunch** brings up the new version. Run that
  copy outside `/Applications` so your installed copy stays as it is.

When testing on a machine that runs Tuckaway daily: export the prefs domain
first (`defaults export com.brunoalumn.tuckaway backup.plist`), quit the
installed app, test the dev build, then re-import and relaunch.

## Release

1. Verify the stack: every PR reviewed, builds green, behavioral checks above run.
2. Bump `MARKETING_VERSION` (all four Tuckaway configurations) and
   `CURRENT_PROJECT_VERSION` in the project file.
3. Build the GitHub release with `scripts/package-dmg.sh`. It builds
   `Release-Direct` (universal), refuses Debug or sandboxed builds, and writes
   `dist/Tuckaway.dmg`. Set `SIGN_IDENTITY` to a Developer ID to sign, then
   notarize and staple the DMG. Publish a GitHub release tagged `v<version>`
   with **`Tuckaway.dmg`** as the asset (no zip) and notes listing closed
   issues. Never publish a build from the **Tuckaway App Store** scheme there:
   it is the sandboxed build, which can't hide on macOS 27 (a past release made
   that mistake). The script refuses it; to check a build by hand:

   ```sh
   codesign -d --entitlements - 'Tuckaway.app' | grep app-sandbox  # must print nothing
   ```

   The in-app updater installs this DMG, so it must hold `Tuckaway.app` at its
   root, its `CFBundleShortVersionString` must equal the release tag
   (`v1.1.0` ↔ `1.1.0`), and `codesign --verify --deep --strict` must pass. The
   script checks all of this except the tag. (The v1.0.0 asset was a zip of a
   Debug build; the updater still accepts zips so v1.0.0 users can update.)
4. App Store (separate lane, **Tuckaway App Store** scheme): Tuckaway has no
   App Store listing, and Hidden Bar's belongs to its original maintainers
   (#393). The sandboxed build also can't hide on macOS 27, so decide
   deliberately before starting one.
5. Homebrew: there is no Tuckaway cask yet (`hiddenbar` installs the original
   app). A cask would follow the GitHub DMG; notarization matters (issue #219).
6. Before a public release: one upgrade-path run from a launcher-era Hidden Bar
   (v1.9 or older) verifying System Settings shows no ghost
   LauncherApplication login item.

## Stacked-PR hygiene

PRs target `main`. When changes stack (`main <- A <- B`), merge the base PR
first, then retarget the next PR's base to `main` BEFORE merging it; deleting a
merged branch auto-closes dependents otherwise.

## Issue triage map

The live clusters and their code areas are documented at the end of
[ARCHITECTURE.md](ARCHITECTURE.md#known-architectural-limits): macOS 27's
per-app, private-API hiding and its side effects, the App Store build on 27,
the notch, and pointer-vs-open-menu limits. Upstream Hidden Bar issues and
where each landed are in [UPSTREAM_ISSUES.md](UPSTREAM_ISSUES.md). Memory reports (#361 et al.)
have so far not reproduced as leaks (constraint-leak fix landed; `leaks` clean
over toggle stress); re-check with a 24h+ uptime `footprint` sample before
chasing further.
