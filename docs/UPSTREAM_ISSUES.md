# Upstream issue integration status

Tracks the open-issue queue from `dwarvesf/hidden` and the corresponding pull
requests in `Bruno-Alumn/Tuckaway`. It does not modify or close upstream issues.

## Merged fix PRs

| Fork PR | Upstream issues addressed |
|---|---|
| #1 | Existing local macOS 27, native-hiding, localization, and CoreSpeech fixes |
| #2 | All 23 upstream PRs open at integration time |
| #3 | #456 legacy login-item cleanup retry |
| #4 | #429 Accessibility timeout / fail-open inventory |
| #5 | #434 right-click toggling |
| #6 | #457 empty-menu-bar toggling |
| #7 | #310 selectable expand icons, also covers #173 and the icon part of #332 |
| #8 | #286 and #304 app-icon proportions, also covers #198 |
| #9 | #232 external-display behavior |
| #10 | #423 Dock icon during expansion |
| #11 | #248 hover-to-expand preference |
| #12 | #299 separator visibility command, also covers #168 and #212 |
| #13 | #182 collapse on application focus change |

PRs #1 and #2 also cover the existing native macOS 27 fixes (#409, #410, #411,
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
- **#219 notarization and #220/#197 automatic updates:** require Developer ID
  signing, notarization credentials, and a signed update feed. The local Mac has
  no valid code-signing identity, so these cannot be completed safely as local
  code-only changes.
- **#326, #361, and #386 memory reports:** the latest merged build completed 40
  real expand/collapse cycles with zero leaked bytes, a 40.5 MB physical
  footprint, and no swapped memory. A long-uptime footprint sample is still
  needed before claiming these long-running reports fixed; an automatic restart
  script is not a memory-leak fix.
