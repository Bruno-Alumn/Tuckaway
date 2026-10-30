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

## Remaining implementation work

- **#229 activity-based reveal:** needs a design that observes changing icon
  content without continuously expanding the real menu bar or weakening the
  existing Screen Recording and Accessibility permission boundaries.

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
