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

When testing on a machine that runs Tuckaway daily, quit the installed app and
back up its settings by file path:

```sh
defaults export ~/Library/Preferences/com.brunoalumn.tuckaway.plist backup.plist
```

Test the dev build, then quit it and restore. `import` merges into what is
there, so delete first:

```sh
defaults delete ~/Library/Preferences/com.brunoalumn.tuckaway.plist
defaults import ~/Library/Preferences/com.brunoalumn.tuckaway.plist backup.plist
```

Don't use the bare domain name (`defaults export com.brunoalumn.tuckaway`). On a
Mac that has ever run the App Store build, `defaults` then reads and writes the
leftover sandbox container
(`~/Library/Containers/com.brunoalumn.tuckaway/…`), which the direct build never
reads.

## Release

1. Verify the stack: every PR reviewed, builds green, behavioral checks above run.
   Check main's own CI too (`gh run list --branch main --event push --limit 3`):
   packaging and verifying the DMG only runs on pushes to main, so a PR can be
   green while main is red. It was red from #61 to #100 without anyone noticing.
2. Bump `MARKETING_VERSION` (all four Tuckaway configurations) and
   `CURRENT_PROJECT_VERSION` in the project file. In the same PR, rename
   `## Unreleased` in `CHANGELOG.md` to `## v<version> (<date>)` and start a
   new empty `## Unreleased` above it: "What's New" is built from that section,
   and `package-dmg.sh` refuses to package a version without one.
3. Build the GitHub release with `EXPECTED_VERSION=v<version> scripts/package-dmg.sh`.
   The expected tag is rejected if it differs from the app's
   `CFBundleShortVersionString`. The script builds
   `Release-Direct` (universal), refuses Debug or sandboxed builds, signs the
   app with the **Tuckaway Release Signing** certificate, or the Developer ID
   when `SIGN_IDENTITY` names it (see [Release signing](#release-signing)), and
   writes `dist/Tuckaway.dmg`. It refuses to run without the certificate. A
   Developer ID build is also notarized (`notarytool` profile
   `tuckaway-notary`) and stapled. Publish a GitHub release tagged `v<version>`
   with **`Tuckaway.dmg`** as the asset (no zip) and notes listing closed
   issues. Verify the published asset with `scripts/verify-release-digest.sh v<version>`.
   The update alert shows the first ~700 characters of the notes as
   plain text, skipping any "Install" or "Download" section, so put what
   changed first. Never publish a build from the **Tuckaway App Store** scheme there:
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

   Then exercise the same mount-copy-eject path the updater uses, which catches
   images that unmount before their contents can be read:

   ```sh
   scripts/verify-dmg.sh dist/Tuckaway.dmg com.brunoalumn.tuckaway v<version>
   ```
4. App Store (separate lane, **Tuckaway App Store** scheme): Tuckaway has no
   App Store listing, and Hidden Bar's belongs to its original maintainers
   (#393). The sandboxed build also can't hide on macOS 27, so decide
   deliberately before starting one.
5. Homebrew: after publishing, run `scripts/update-cask.sh --publish`. It sets
   the version and sha256 in `packaging/tuckaway.rb` from GitHub's digest of
   the uploaded DMG and pushes the cask to the tap,
   [Bruno-Alumn/homebrew-tuckaway](https://github.com/Bruno-Alumn/homebrew-tuckaway).
   Commit the changed `packaging/tuckaway.rb` in a PR. (`hiddenbar` in
   Homebrew's own casks installs the original app.)
6. Before a public release: one upgrade-path run from a launcher-era Hidden Bar
   (v1.9 or older) verifying System Settings shows no ghost
   LauncherApplication login item.

## Release signing

Every release is signed with the same designated requirement,
`Updater.releaseRequirement`: bundle ID `com.brunoalumn.tuckaway`, signed
either by the self-signed **Tuckaway Release Signing** certificate (releases
from 1.2 on) or by the maintainer's **Developer ID Application: Bruno Cassina
(22R95V8NA5)**. `package-dmg.sh` reads it from `Updater.swift` and signs with
it explicitly, so:

- Accessibility and Screen Recording grants, and firewall rules, survive
  updates signed by the same certificate, and grants made under a release that
  carries the combined requirement (1.10.0 on) survive the switch from one
  certificate to the other (see below for older grants);
- the updater only installs an update that satisfies the running app's
  designated requirement, so a tampered or differently signed download is refused.

Releases up to 1.1.0 were ad-hoc signed; updating from one of them to a
certificate-signed release asks for permissions once.

### Moving to Developer ID

Releases up to the one that adds the combined requirement have a requirement
naming only the release certificate, so their updater refuses a Developer ID
build. So the move takes two releases:

1. **Bridge release:** signed with Tuckaway Release Signing as usual
   (`scripts/package-dmg.sh`), now carrying the combined requirement. Users get
   it through the updater.
2. **Every release after:** `SIGN_IDENTITY="Developer ID Application: Bruno Cassina (22R95V8NA5)" scripts/package-dmg.sh`.
   It's notarized and stapled, so the first-launch "Open Anyway" step goes away.
   Users on the bridge release update in place. Anyone still on an older
   release has to download it by hand.

**One re-grant is unavoidable for older permissions.** macOS stores the
requirement in force *when a permission was granted*, and running a newer build
doesn't update it. A grant made under 1.9.0 or earlier names only the release
certificate, so the first Developer ID build loses it, though its switch stays
on in System Settings. A grant made under 1.10.0 or later carries over. (Tested
in a VM for ThockBox, which made the same move: Accessibility granted before
its bridge release was lost, a grant made under the bridge build was kept.)

Tuckaway handles this at launch (`Updater.resetStaleGrantsAfterSigningChange`):
it records the SHA-256 of its leaf signing certificate, and on the first launch
with a different one (or, with none on record, on a Developer ID build) it runs
`tccutil reset` for Accessibility and Screen Recording if they don't work, then
asks for Accessibility again. The first Developer ID release must include this
code, since 1.10.0 doesn't.

Developer ID setup on a new Mac: install the certificate (and Apple's
**Developer ID - G2** intermediate if `codesign` reports "unable to build
chain"), then save the notarization login once with
`xcrun notarytool store-credentials tuckaway-notary --apple-id <Apple ID> --team-id 22R95V8NA5`
and an app-specific password from account.apple.com. Back up the Developer ID
certificate as a `.p12` too.

**Back up the key now.** If it is lost, the next release has to use a new
certificate. Every user then gets asked for permissions again, and the updaters
already installed refuse that release, so everyone has to download it by hand.

1. Open Keychain Access, choose **login**, then **My Certificates**.
2. Right-click **Tuckaway Release Signing**, choose **Export…**, and save it as
   a `.p12` with a strong password.
3. Keep the `.p12` and its password somewhere safe and offline, such as a
   password manager or an encrypted drive. Never commit it.

To sign on another Mac, double-click the `.p12` there and enter the password.
`security find-identity -p codesigning` should then list the certificate.
"CSSMERR_TP_NOT_TRUSTED" is expected for a self-signed certificate and doesn't
stop signing.

The release certificate is valid until October 2046. Keep it even after the
move to Developer ID: the requirement still names it, and losing it doesn't
matter once every user is past the bridge release.

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
