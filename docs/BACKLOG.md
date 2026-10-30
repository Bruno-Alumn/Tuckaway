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
  clock, displays, keyboard, volume, wifi, screenMirroring, primaryBentoBox. The clock
  and other MenuBarAgent items expose no AX actions, so the clock cannot be pressed
  through Accessibility. Shipped mitigation: no restriction while a mic or camera is in
  use (`CaptureActivityMonitor`). Still open: Now Playing / Live Activities hidden, clock
  click inert, screen recording not detected (no public API). Revisit if Apple adds an
  origin or a public API.
- **App Store build can't hide on 27.** The sandbox denies `mach-lookup
  com.apple.axserver`, so the sections can't be read even with Accessibility granted
  (measured 2026-09-18). Options: a user-picked list of visible apps instead of ⌘-drag
  (no Accessibility, still private API), a public mechanism if Apple ships one, or
  dropping the App Store lane.

## Releases and distribution

- **Developer ID signing and notarization (#219).** Removes the Open Anyway step.
  Permissions already survive updates through the self-signed release certificate.
- **Homebrew cask** pointing at the GitHub DMG, once notarized.
- **Upgrade-path login-item check.** Install a launcher-era Hidden Bar (v1.9 or older),
  then Tuckaway, and confirm Login Items shows no leftover `LauncherApplication` row.
  The one-time deauthorization has never been run on hardware.

## Verification still owed

- **#351 external-monitor visible bar (26.4).** The widest-attached-screen fix is
  code-only; confirm no full-width bar leak on a real second monitor.
- **24h memory dogfood (#361, #326, #386).** Stress cycling found no leak; a long-uptime
  `footprint` sample is still needed before calling these fixed.

## Features

- **#207 show the clock/date when collapsed.** The loudest single feature request.
- **#229 activity-based reveal.** Needs a design that notices changing icon content
  without continuously expanding the real menu bar.
- **Always-hidden section rework.** Always-hidden items are only reliably hidden when
  "hide separators" is on (see the note in [MANUAL.md](MANUAL.md)). Decouple the two
  and add a way to recover a stuck off-screen item. Reproduce #242 (permanent icon
  loss) with a throwaway defaults profile first.
- **Always Hidden list in Menu Bar Items.** The window shows only Hidden and Visible,
  so icons in the always-hidden section appear under Hidden and can't be moved into
  it. Add a third list while the section is on. The mover anchors an empty list to
  Tuckaway's own item, so it needs the always-hidden separator's frame as well. On
  macOS 27 that separator leaves the bar while its section is hidden, so the window
  has to show the section first. Test on a real bar; it moves icons.
- **Separate hidden-items bar on macOS 27.** Turned off there (#30): macOS 27 draws
  status items into the menu bar, so there are no per-item windows to capture.
  Capturing the menu-bar strip at the items' Accessibility frames, which the
  inventory already reads, could bring it back.

## Done since the Hidden Bar fork

Kept here so they aren't re-filed: hover-to-expand checkbox; login-item failures
surfaced in Settings; VoiceOver can toggle the arrow (`AXPress` with no event);
macOS 27 tutorial text; single-instance guard (#324); ⌘W closes Settings (#276);
settings layout overlap (#355, Settings redesign); notch overflow and the separate
hidden-items bar; native macOS 27 hiding (#360); automatic updates (#220, #197);
certificate-signed releases (1.2.0); every string translated into all 13 languages,
enforced by `LocalizationTests`.
