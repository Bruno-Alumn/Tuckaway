# Upstream issue integration status

Tracks the open-issue queue from `dwarvesf/hidden` and where each fix landed in
Tuckaway. It does not modify or close upstream issues. Issue numbers (`#123`)
refer to `dwarvesf/hidden` unless a link says otherwise.

## Merged fixes

The first round of fixes was merged before the repository was recreated, so
those pull-request numbers no longer resolve on GitHub (and today's #1–#7 are
different PRs). The branches and merge commits below are the stable references.

| Branch (merge commit) | Upstream issues addressed |
|---|---|
| `integration/community-prs-and-local-fixes` (`b8ca9eb`) | Existing local macOS 27, native-hiding, localization, and CoreSpeech fixes |
| `integration/upstream-pr-attribution` (`97212bf`) | All 23 upstream PRs open at integration time, with author attribution |
| `fix/issue-456-legacy-login-item` (`22e1033`) | #456 legacy login-item cleanup retry |
| `fix/issue-429-inventory-fail-open` (`2469aea`) | #429 Accessibility timeout / fail-open inventory |
| `fix/issue-434-right-click-toggle` (`ab4d4a2`) | #434 right-click toggling |
| `feature/issue-457-empty-menu-bar-toggle` (`64bbdf1`) | #457 empty-menu-bar toggling |
| `feature/issue-310-expand-icon-styles` (`e870154`) | #310 selectable expand icons, also covers #173 and the icon part of #332 |
| `fix/issue-286-app-icon-padding` (`5c1bcf1`) | #286 and #304 app-icon proportions, also covers #198 |
| `feature/issue-232-external-display-preference` (`6d5aa31`) | #232 external-display behavior |
| `fix/issue-423-dock-icon-expansion` (`2461c71`) | #423 Dock icon during expansion |
| `feature/issue-248-hover-preference` (`af9fc02`) | #248 hover-to-expand preference |
| `feature/issue-299-separator-menu-toggle` (`0f77684`) | #299 separator visibility command, also covers #168 and #212 |
| `feature/issue-182-collapse-on-focus-change` (`0b09b06`) | #182 collapse on application focus change |
| [Bruno-Alumn/Tuckaway#1](https://github.com/Bruno-Alumn/Tuckaway/pull/1) | #355 settings layout overlap (compact Settings redesign) |
| [Bruno-Alumn/Tuckaway#3](https://github.com/Bruno-Alumn/Tuckaway/pull/3), [#7](https://github.com/Bruno-Alumn/Tuckaway/pull/7) | #220 and #197 automatic updates (GitHub releases updater, DMG releases) |

The two integration branches also cover the existing native macOS 27 fixes (#409, #410, #411,
#412, #413, #414, #421, #424, #426, #428, #430, #431, #435, #436's documented
limitation, #439, #440, #442, #443, #444, #446, #448, #451, #454, and #458),
notch and overflow requests (#174, #206, #225, #228, #245, #267, #269, #280,
#292, #330, #341, #357, and #366), ordering and always-hidden fixes (#171,
#181, #205, #224, #231, #233, #239, #242, #252, #254, #263, #275, #283, #288,
#302, #321, and #334), and other previously implemented requests (#170, #199,
#249, #291, #295, #302, #309, #319, #324, #336, #355, and #390).

Since 1.8.0: #207 (Settings explains the clock's dropped date on macOS 13–26
and opens Clock Options), #229 (hidden icons whose width or text changes show
for a moment, macOS 27), and #159 (spacers). Already covered by earlier work:
#432 (no restriction while a microphone or camera is in use; screen recording
is #372 below), #107 (new apps are asked about on macOS 27), #99 (expand icon
styles, #310), and #153 (Settings no longer opens at every launch by default).

## Remaining implementation work

- **#229, picture-only changes:** an icon whose picture alone changes isn't
  visible to Accessibility, and hidden icons aren't drawn for Screen Recording.
- **#154 "shown when inactive" group:** on macOS 27 it would mean holding a
  restriction while expanded, which brings assessment mode's side effects
  (Now Playing, Live Activities) into the expanded bar too.
- **#104 and #143:** #104 is what "Expand across full menu bar" already does,
  and #143 (its label was unclear) is answered by the caption under it.
- **Separator engine only (macOS 13–26), not reproducible on 27:** #156 and
  #369 (icons drifting back into a hidden section), #230 (icons the separator
  doesn't push), #375 (WindowServer crashes on 26.5, like #175), and #148 (a
  second bar so system icons at the end stay visible; macOS 27 hides by app,
  not position). Each needs a 13–26 Mac to reproduce.
- **#142:** "Expand across full menu bar" while an app is full screen hides
  the menu bar. Needs testing in a full-screen Space.
- **#100 (more sections with their own shortcuts):** profiles (shortcut each)
  cover switching between sets of visible apps on macOS 27; extra positional
  sections would only apply to the separator engine.
- **#380 (notch hides icons on a MacBook Air):** Show Notch Items / Notch
  Overflow lists icons the notch covers; whether it helps this report's setup
  is unconfirmed.
- **#28 (show an app's icon after it updates):** built for macOS 27 (an option
  under Revealing). The separator engine can't show one app on its own.

## What `MenuBarClientCore` exposes (read 2026-11-03, macOS 27.2)

Class and method names read from the private framework, not behaviour that was
measured. Kept so the next report about #427 doesn't start from nothing.

- `MBAssessmentModeConfiguration` takes `allowedSystemItems` and
  `allowedBundleIdentifiers` (or an unrestricted init), so a restriction is a
  list of apps. That is why #427 is blocked.
- The assertion also has `activate:completion:`. *Guess:* it takes
  `MBMenuBarItem`s (`itemID`, `content`, `tags`), which would be per status
  item. Neither the argument type nor what `itemID` means to MenuBarAgent has
  been confirmed, and nothing uses it.
- `MBMenuBarItemManager` has `lockMenuPositionWithToken:`,
  `navigateInDirection:` and `setItems:`, next to methods such as
  `setFullScreenHidden:forSpaceID:` and `startMenuTrackingForItemID:`. *Guess:*
  this is the menu bar host's own interface rather than one a client app can
  drive. Whether it could move another app's icon is unknown.
- The side effects in #437 were measured on 27.0 (see BACKLOG.md). Nothing new
  was measured here.

## External or OS blockers

- **#427 per-icon control within one app:** macOS 27's native visibility
  restriction accepts bundle identifiers, not individual status-item IDs.
  Restoring per-icon control needs a new Apple API or a different hiding
  mechanism; the current API cannot represent it.
- **#333, #327, and the Live Activity part of #332:** assessment mode hides
  Live Activities even when their owning app is allow-listed. #436 is the same
  limitation for Now Playing. The current engine preserves the behavior only as
  a documented OS limitation, not a fix.
- **#372 active screen sharing:** there is no public screen-recording activity
  signal equivalent to the microphone and camera monitors. Hiding this system
  indicator independently is not available through the current native API.
- **#393 App Store version:** requires the upstream App Store account and a
  release decision. The fork cannot publish to the original listing.
- **#219 notarization:** requires a Developer ID and notarization credentials.
  Releases are signed with a stable self-signed certificate instead, so
  permissions survive updates, but Gatekeeper still shows "Open Anyway" on first
  launch. (Automatic updates, #220/#197, ship without notarization; see above.)
- **#326, #361, and #386 memory reports:** the latest merged build completed 40
  real expand/collapse cycles with zero leaked bytes, a 40.5 MB physical
  footprint, and no swapped memory. A long-uptime footprint sample is still
  needed before claiming these long-running reports fixed; an automatic restart
  script is not a memory-leak fix.
