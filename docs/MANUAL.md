# Manual

Everything Hidden Bar can do, including the parts with no UI.

## Basics

- **Left-click the arrow** (`<` / `>`): expand or collapse the hidden section.
- **Right-click the arrow** or **left-click the separator** (`|`): context menu
  (Preferences, Toggle Auto Collapse, Quit).
- **⌘-drag** icons in the menu bar to move them across the separator: icons to
  the separator's left are hidden when collapsed.
- **Option-click the arrow**: show/hide the separators and the always-hidden
  area without expanding.

### macOS 27, direct download build

The direct (non-App Store) build hides icons natively on macOS 27, and the
**arrow itself is the boundary**: there is no `|` separator. ⌘-drag icons to
the arrow's left to hide them when collapsed, to its right to keep them
visible. The always-hidden separator still appears (while expanded) when that
section is enabled.

- Needs **Accessibility** permission (System Settings › Privacy & Security ›
  Accessibility) to see where your icons are. Without it the bar stays
  expanded.
- Hiding is per app: an app with several icons hides or shows them together.
- These macOS items always stay visible: clock, Control Center, Wi-Fi,
  Bluetooth, Sound, Battery, Display, Keyboard and Screen Mirroring.
- With more than one display, an app stays visible if it is on the arrow's
  visible side on **any** display. If Hidden Bar cannot read a complete display
  layout after a monitor change, wake, or app launch, it leaves the bar expanded
  until it can safely read it again.
- Clicking the clock opens Notification Center as usual. macOS ignores the
  clock while it hides icons this way, so Hidden Bar lifts the hiding for a
  moment and clicks the clock for you; the hidden icons show for under a
  second while it does.
- Run Hidden Bar from `/Applications`; macOS only recognizes that copy as
  Hidden Bar, and a copy elsewhere hides its own arrow.

#### While collapsed (macOS limitation, #437)

macOS 27 offers this kind of hiding only as part of its exam-lockdown
(assessment) mode, and turns on that mode's other restrictions too. Hidden Bar
cannot opt out of them. While the arrow is collapsed:

- **Now Playing and Live Activities are hidden**, even if you keep the app that
  is playing to the right of the arrow.
- **Clicking the clock briefly reveals hidden icons.** Hidden Bar lifts the
  restriction, presses the clock to open Notification Center, then restores
  hiding; the icons can remain visible for under a second.
- **Recording indicators:** macOS hides the menu-bar indicator that names the
  app using the microphone or camera (the orange or green capsule). The small
  colored dot in the top-right corner of the screen still shows. To keep the
  capsule too, Hidden Bar stops hiding and shows the whole bar as soon as an
  app starts using the microphone or a camera, and resumes when that stops.
  macOS's always-on CoreSpeech listener is ignored because it does not show a
  recording indicator. The arrow keeps its collapsed look in the meantime.
- **Screen recording: not covered.** macOS offers no public way to tell that
  another app is recording the screen, so Hidden Bar keeps hiding. The purple
  dot in the screen corner still shows.

Expanding the arrow ends all of this immediately.

## Preferences window

| Setting | What it does |
|---|---|
| Start Hidden Bar when I log in | Login item via System Settings (macOS 13+ `SMAppService`); revocable in System Settings > General > Login Items |
| Show preferences on launch | Open this window at app start |
| Auto collapse | Re-hide automatically after the chosen delay |
| Hover to expand | Expand after hovering over the menu bar for about half a second |
| Global shortcut | System-wide expand/collapse hotkey (F-keys display as F18, not Fn18) |
| Enable always hidden section | A second zone whose icons stay hidden even when expanded; revealed by option-clicking the arrow |
| Use full menu bar on expanding | Activates the app's full menu bar while expanded without adding a Dock icon (helps on tight menubars) |
| Show hidden items in separate bar | Captures hidden icons into a floating row below the menu bar; requires Screen Recording, and Accessibility for click forwarding |
| Manage Menu Bar Items | Opens two sortable lists for hidden and visible items; drag within a list to reorder or across lists to change visibility; requires Accessibility permission |

> **Always-hidden section, current behavior:** items in the always-hidden zone
> are reliably pushed off-screen only when "hide separators" is also on
> (option-click the arrow). With the separators visible, always-hidden items can
> still appear after expanding. This coupling is a known limitation being
> reworked alongside the menu-bar redesign; for now, option-click to hide the
> separators if always-hidden items keep showing. Avoid placing critical icons in
> the always-hidden zone until the rework lands, since a stuck off-screen item has
> to be recovered by ⌘-dragging it back (macOS persists its position per app).

## Behaviors you get for free

- **It won't collapse mid-use**: while your pointer is anywhere in the menu bar,
  the auto-collapse countdown defers and restarts; it resumes when you leave.
- **Self-repair**: if the arrow or separator was ⌘-dragged off the bar (which
  used to make the app unreachable forever), they come back on next launch.
- **Display changes**: plugging in or removing monitors re-sizes the hidden zone
  for the widest attached screen automatically.

## Hidden settings (Terminal)

All via `defaults`; quit and relaunch the app after changing them.

```sh
# auto-collapse delay in seconds (the UI offers a fixed list; any value works)
defaults write com.dwarvesv.minimalbar numberOfSecondForAutoHide -float 5

# force the app language regardless of system order (issue #287)
defaults write com.dwarvesv.minimalbar AppleLanguages '(en)'
```

To undo any of them: `defaults delete com.dwarvesv.minimalbar <key>`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Icons I want visible got hidden after an update | On macOS 27 direct builds, ⌘-drag them to the arrow's right; on earlier builds, drag them right of the separator |
| Login item missing after denying it once | System Settings > General > Login Items: re-enable Hidden Bar, then toggle the pref off/on |
| A ghost "LauncherApplication" login item from old versions | Launch the current version once; it deauthorizes the legacy item automatically |
| App language stuck | See the `AppleLanguages` command above, or System Settings > General > Language & Region > Applications |
| Nothing hides on a macOS 27 beta | Known (issue #360); the menu bar re-architecture broke the hiding mechanism, fix under investigation |
| A new or just-updated app's icon shows up already hidden | Expected, see "Why new icons start hidden" below; ⌘-drag it to the right of the separator once |

### Why new icons start hidden

Hidden Bar hides icons by widening its separator so everything to the *left* of
it slides off-screen. macOS always inserts a brand-new menu-bar icon at the
far-left slot, which is inside that hidden zone, so a freshly launched or updated
app can appear "swallowed". This is macOS positioning behavior, not Hidden Bar
moving your icon: there is no way for one app to reposition another app's menu-bar
icon. The one-time fix is to ⌘-drag the icon to the right of the separator;
macOS remembers that placement per app. A built-in way to keep chosen icons
pinned is being explored as part of the larger menu-bar redesign.

## Requirements

macOS 13 Ventura or later. Pre-Ventura (10.13 - 12.x): use
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10), the last release
on the old autostart mechanism.
