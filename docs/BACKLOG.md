# Backlog

Open work for Tuckaway, one line per item, pointing at the issue or file that
holds the detail. Issue numbers (`#123`) are `dwarvesf/hidden` issues unless
linked otherwise. Changes to the core model (separator length math, collapse
state machine, the native engine) are high risk: test them on a real menu bar
before merging.

## macOS 27 (#360)

- **Direct build ships native hiding** (`NativeVisibilityEngine`, Debug-Direct /
  Release-Direct configurations). Uses private `MenuBarClientCore`; not App Store safe.
- **Assessment-mode side effects (#437) have no fix in MenuBarClientCore.** Measured
  on 27.0 (26A428), 2026-09-25. `MBAssessmentModeAssertion` sends
  `acquireAssertionWithID:origin:allowedSystemItems:allowedBundleIdentifiers:` to
  MenuBarAgent (mach `com.apple.MenuBarAgent.systemservices`, service
  `com.apple.MenuBarAgent.visibility-restriction`), with origin `@1`. The other origins:
  `0` (userSessionTransition) is accepted but ignores the allow-list and hides nothing;
  `2` (campoDrag) is rejected (`VisibilityRestrictionError.activation`). MenuBarAgent
  ORs the origin flags of all live restrictions, so any assessment restriction brings the
  side effects. The system-item range 0..<64 resolves to 9 names: battery, bluetooth,
  clock, displays, keyboard, volume, wifi, screenMirroring, primaryBentoBox. Shipped
  mitigations: no restriction while a mic or camera is in use (`CaptureActivityMonitor`),
  and `SystemMenuBarClock` presses the clock through Accessibility with the restriction
  briefly lifted. Still open: Now Playing / Live Activities hidden and screen recording
  not detected (no public API). Revisit if Apple adds an origin or a public API.
- **App Store build can't hide on 27.** The sandbox denies `mach-lookup
  com.apple.axserver`, so the sections can't be read even with Accessibility granted
  (measured 2026-09-18). Options: a user-picked list of visible apps instead of ⌘-drag
  (no Accessibility, still private API), a public mechanism if Apple ships one, or
  dropping the App Store lane.

## Releases and distribution

- **Developer ID signing and notarization (#219).** Removes the Open Anyway step.
  Permissions already survive updates through the self-signed release certificate.
- **Homebrew cask in Homebrew's own repository**: Tuckaway has its own tap
  (`bruno-alumn/tuckaway`); homebrew-cask itself needs a notarized app.
- **Upgrade-path login-item check.** Install a launcher-era Hidden Bar (v1.9 or older),
  then Tuckaway, and confirm Login Items shows no leftover `LauncherApplication` row.
  The one-time deauthorization has never been run on hardware.

## Verification still owed

- **Features not yet used in the running app:** see
  [HANDS_ON_CHECKS.md](HANDS_ON_CHECKS.md).

- **Open review findings (2026-11-02), not fixed.** Checked since on 27.2: the
  legacy login-item cleanup did succeed on the owner's Mac (`smAppServiceMigrated`
  is set), so it doesn't retry there; left-to-right status-item positions are
  distances from the right edge (Battery 179 left of Control Center 137), as the
  repair assumes. Still open: Notch Overflow's boundary comes
  from `auxiliaryTopRightArea`, whose coordinate space is unverified when the
  notched display isn't the primary one (icons on other displays are left out
  since #109); the Hidden Bar settings migration may find nothing for users
  of the sandboxed App Store Hidden Bar (won't fix: its settings are in its
  sandbox container, and reading another app's container makes macOS 14+ ask
  for "data from other apps" on first launch); right-to-left, the repair assumes
  positions are distances from the left edge, which needs an RTL system
  language to confirm. Each needs hardware or a fixture to confirm.

- **⌘-dragging past the arrow on macOS 27.** Synthesized drags never passed Tuckaway's
  own arrow rightward (27.2), so moves into Visible now mark the app instead (#93).
  Leftward (Visible → Hidden) was never seen failing but wasn't tested either.
- **Separate bar with several displays and on notched Macs** (captures by the
  Accessibility frames of the arrow's display only).
- **Presentation-mode shortcut and the shortcut recorder's second row**: key presses
  can't be synthesized from the agents' shell, so only the menu path was tested.

- **#351 external-monitor visible bar (26.4).** The widest-attached-screen fix is
  code-only; confirm no full-width bar leak on a real second monitor.
- **24h memory dogfood (#361, #326, #386).** Stress cycling found no leak; a long-uptime
  `footprint` sample is still needed before calling these fixed.

## Features

- **#229, picture-only changes.** Activity reveal (macOS 27) notices width and
  text changes through Accessibility; an icon whose picture alone changes (a
  badge dot) would need Screen Recording, and hidden icons aren't drawn.
- **Profiles by Focus.** Reading which Focus is on needs the Communication
  Notifications entitlement, which only a Developer ID (#219) can carry
  ([PROFILES.md](PROFILES.md)).
- **Always-hidden section rework.** Always-hidden items are only reliably hidden when
  "hide separators" is on (see the note in [MANUAL.md](MANUAL.md)). Decouple the two
  and add a way to recover a stuck off-screen item. Reproduce #242 (permanent icon
  loss) with a throwaway defaults profile first.

## Done since the Hidden Bar fork

Kept here so they aren't re-filed: hover-to-expand checkbox; login-item failures
surfaced in Settings; VoiceOver can toggle the arrow (`AXPress` with no event);
macOS 27 tutorial text; single-instance guard (#324); ⌘W closes Settings (#276);
settings layout overlap (#355, Settings redesign); notch overflow and the separate
hidden-items bar; native macOS 27 hiding (#360); automatic updates (#220, #197);
certificate-signed releases (1.2.0); every string translated into all 13 languages,
enforced by `LocalizationTests`; an Always Hidden list in Menu Bar Items; the separate
hidden-items bar on macOS 27, with hover, app names, VoiceOver and a right-click menu;
new apps asked about instead of hidden unseen (macOS 27); presentation mode (macOS 27);
the updater retries its relaunch; spacers (#159); activity reveal (#229, width and
text changes); profiles by time of day; renaming and editing profiles; the clock's dropped date while collapsed (#207)
explained in Settings, with a button to Clock Options (macOS 13–26; 27 isn't affected).

## New ideas (2026-11-03 round)

From a brainstorm by another agent (#145), updated after review. Anything that
needs a paid Developer ID, a server, or collecting data was left out.

Built or in review:

- **Undo the new-app answer** for five minutes from the arrow's menu (#155).
- **A rescue panel when the arrow is lost** (macOS 13–26): after
  `rescueArrowIfSwallowed`'s two repairs fail, a panel offers Repair, Settings,
  Quit or Later instead of looping (#156).
- **Check Your Setup** in Settings › General (#158).
- **What's New** after an update, from the bundled changelog (#157).
- **Menu Bar Items groups an app's icons** into one row on macOS 27.

Still open:

1. **Open a hidden icon's menu with `AXShowMenu` from the separate bar.**
   - *Problem:* a click is sent at a position. `clickNativeHiddenItem` already
     re-reads positions just before clicking, so this is about the few cases
     where that read itself is stale.
   - *Size:* M. The native click path and `AccessibilityMenuBarInventory`.
   - *Risks:* unknown whether MenuBarAgent honours `AXShowMenu` while the
     restriction is held (it ignores accessibility presses then,
     `MenuBarClock.swift`), and not every app implements it, so the click
     fallback stays. Measure before building.
2. **A hiding engine for macOS 26 and earlier that doesn't rely on the
   separator's length.** #144 tried this with the private
   `activate:completion:` call and was closed: it changed the macOS 27 expand
   path for everyone and never got past a stub. Needs a measured design first.

Dropped, with the reason:

- **A `|` separator on macOS 27** (#151): everything left of the arrow is
  hidden there, so a mark on that side separates nothing.
- **Hiding in the App Store build on 27 from a list of apps** (#152): needs a
  private framework (App Review 2.5.1) and reading other apps' accessibility
  trees, which the sandbox blocks.
- **Per-icon hiding within one app** (#427): macOS 27's restriction takes
  bundle identifiers.
- **A "shown when inactive" group** (#154): needs a restriction held while
  expanded, which brings assessment mode's side effects (Now Playing, Live
  Activities) into the expanded bar.
- **Noticing screen recording** (#372) and **picture-only icon changes**
  (#229): no public signal, and hidden icons aren't drawn.
- **A per-app "hide after N minutes"**: nobody asked, and auto-collapse covers it.
- **Exporting the layout as a file**: icon positions belong to macOS, so the file
  would promise more than it can restore.
- **Hiding macOS's own items** (battery, Wi-Fi): the system items on the
  allow-list keep the bar usable, and #437 shows what goes wrong when more of
  them go.

