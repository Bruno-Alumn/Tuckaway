# Manual

Everything Tuckaway can do, including the parts with no UI.

## Basics

- **Left- or right-click the arrow** (`<` / `>`): expand or collapse the hidden section.
- **Control-click the arrow** or **click the separator** (`|`): the menu.
  - **Auto-collapse** (checkmark, ⌘T)
  - **Show/Hide separators** (⌘S)
  - **Manage Menu Bar Items…**
  - **Check for Updates…** (direct-download build)
  - **Settings…** (⌘,)
  - **Quit Tuckaway** (⌘Q)

  On Macs with a notch, **Show Notch Items** appears at the top when notch
  overflow is on.
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

- Needs **Device Control and Data Access** permission (System Settings › Privacy
  & Security), called **Accessibility** on earlier macOS versions, to see where
  your icons are. Without it the bar stays expanded.
- Hiding is per app: an app with several icons hides or shows them together.
- These macOS items always stay visible: clock, Control Center, Wi-Fi,
  Bluetooth, Sound, Battery, Display, Keyboard and Screen Mirroring.
- With more than one display, an app stays visible if it is on the arrow's
  visible side on **any** display. A monitor change, wake, or app launch shows
  everything for a moment; about two seconds after things settle, Tuckaway
  re-reads the layout and hides again (it waits while your pointer is in the
  menu bar). If it still can't read a complete layout, the bar stays expanded.
- Clicking the clock opens Notification Center as usual. macOS ignores the
  clock while it hides icons this way, so Tuckaway lifts the hiding for a
  moment and clicks the clock for you; the hidden icons show for under a
  second while it does.
- Run Tuckaway from `/Applications`; macOS only recognizes that copy as
  Tuckaway, and a copy elsewhere hides its own arrow.

#### While collapsed (macOS limitation, #437)

macOS 27 offers this kind of hiding only as part of its exam-lockdown
(assessment) mode, and turns on that mode's other restrictions too. Tuckaway
cannot opt out of them. While the arrow is collapsed:

- **Now Playing and Live Activities are hidden**, even if you keep the app that
  is playing to the right of the arrow.
- **Clicking the clock briefly reveals hidden icons.** Tuckaway lifts the
  restriction, presses the clock to open Notification Center, then restores
  hiding; the icons can remain visible for under a second.
- **Recording indicators:** macOS hides the menu-bar indicator that names the
  app using the microphone or camera (the orange or green capsule). The small
  colored dot in the top-right corner of the screen still shows. To keep the
  capsule too, Tuckaway stops hiding and shows the whole bar as soon as an
  app starts using the microphone or a camera, and resumes when that stops.
  macOS's always-on CoreSpeech listener is ignored because it does not show a
  recording indicator. The arrow keeps its collapsed look in the meantime.
- **Screen recording: not covered.** macOS offers no public way to tell that
  another app is recording the screen, so Tuckaway keeps hiding. The purple
  dot in the screen corner still shows.

Expanding the arrow ends all of this immediately.

## Settings window

Open it with **Settings…** (⌘,) from the arrow's menu. It has three tabs.

### General

| Section | Setting | What it does |
|---|---|---|
| Hiding | Auto-collapse | Re-hide automatically after a delay. Also a checkmark in the arrow's menu. |
| Hiding | Collapse after | The delay: 5, 10, 15 or 30 seconds, or 1 minute. Shown only while auto-collapse is on. |
| Hiding | Collapse on app switch | Hide again as soon as another app becomes active. |
| Revealing | Hover to expand | Expand after hovering over the menu bar for about half a second. |
| Revealing | Toggle by clicking empty menu bar | Click an empty part of the menu bar to hide or show icons. |
| Revealing | Expand with an external display | Show everything while an external display is connected. |
| Revealing | Shortcut | A system-wide expand/collapse hotkey. Click to record, Esc to cancel, ⓧ to clear. F-keys work on their own. |
| Appearance | Expand icon | Standard arrow, transparent arrow, or an ellipsis. |
| Appearance | Show hidden items in separate bar | Shows hidden icons in a floating row below the menu bar. Needs Screen Recording, plus Accessibility to forward clicks. macOS 13–26 only: macOS 27 no longer gives menu-bar icons their own windows to capture, so the option is hidden there. |
| Appearance | Expand across full menu bar | Activates the app's full menu bar while expanded, without a Dock icon (helps on crowded menu bars). |
| Extra Sections | Always-hidden section | A second zone whose icons stay hidden even when expanded. Option-click the arrow to reveal it. |
| Extra Sections | Icons behind the notch | Notched Macs only. Adds **Show Notch Items** to the arrow's menu, listing icons the notch covers. |
| Startup | Launch at login | A login item (macOS 13+ `SMAppService`), revocable in System Settings › General › Login Items. |
| Startup | Open settings on launch | Show this window every time Tuckaway starts. |
| Updates | Check for updates automatically | Direct-download build only. See [Updates](#updates). |

If Accessibility is missing on macOS 27, a banner at the top of General
explains why nothing hides and links to System Settings.

### Menu Bar Items

Two lists, **Hidden** and **Visible**, of the other apps' menu-bar icons.

- **Drag within a list** to reorder icons.
- **Drag between lists** to change whether an icon is hidden. Tuckaway performs
  the ⌘-drag in the real menu bar for you.
- Use the refresh button after you change the menu bar yourself.
- Needs Accessibility permission. Without it, a **Grant Access** button shows.

### About

Version and build number, links to the source and issue tracker, and **Check
for Updates…** (direct-download build).

> **Always-hidden section, current behavior:** items in the always-hidden zone
> are reliably pushed off-screen only when "hide separators" is also on
> (option-click the arrow). With the separators visible, always-hidden items can
> still appear after expanding. This coupling is a known limitation being
> reworked alongside the menu-bar redesign; for now, option-click to hide the
> separators if always-hidden items keep showing. Avoid placing critical icons in
> the always-hidden zone until the rework lands, since a stuck off-screen item has
> to be recovered by ⌘-dragging it back (macOS persists its position per app).

## Updates

The direct-download build updates itself from
[GitHub releases](https://github.com/Bruno-Alumn/Tuckaway/releases).

- **Automatic checks:** about 10 seconds after launch, at most once a day.
  Turn them off with **Check for updates automatically** in Settings › General.
- **Manual checks:** **Check for Updates…** in the arrow's menu or About, or
  **Check Now** in Settings › General › Updates.
- **When a newer version exists**, you can choose:
  - **Install and Relaunch:** downloads `Tuckaway.dmg`, checks the bundle ID,
    the version and the code signature, replaces the app in place and reopens
    it. If anything fails, the old copy stays.
  - **Later:** asks again on the next check.
  - **Skip This Version:** no more automatic prompts for that version. A manual
    check still offers it.
- If Tuckaway is running from a read-only location (for example straight from
  the disk image), the button becomes **Download** and opens the release page.
- Updates only install if they're signed with the same certificate as the
  copy you're running, so a tampered download is refused.
- Releases are all signed with that one certificate, so macOS keeps
  Tuckaway's permissions (and firewalls such as LuLu keep their rules) across
  updates. Updating from 1.1.0 or earlier is the exception: those releases
  weren't signed this way, so macOS asks once more.

The App Store build has no network access and no updater.

## Behaviors you get for free

- **It won't collapse mid-use**: while your pointer is anywhere in the menu bar,
  the auto-collapse countdown defers and restarts; it resumes when you leave.
- **Self-repair**: if the arrow or separator was ⌘-dragged off the bar (which
  used to make the app unreachable forever), they come back on next launch.
- **Display changes**: plugging in or removing monitors re-sizes the hidden zone
  for the widest attached screen automatically (macOS 26 and earlier). On macOS
  27, Tuckaway re-reads the layout and hides again about two seconds later.
- **One copy at a time**: opening Tuckaway again brings the running copy
  forward instead of starting a second one.

## Hidden settings (Terminal)

All via `defaults`; quit and relaunch the app after changing them.

```sh
# auto-collapse delay in seconds (the UI offers a fixed list; any value works)
defaults write com.brunoalumn.tuckaway numberOfSecondForAutoHide -float 5

# force the app language regardless of system order (issue #287)
defaults write com.brunoalumn.tuckaway AppleLanguages '(en)'
```

To undo any of them: `defaults delete com.brunoalumn.tuckaway <key>`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Icons I want visible got hidden after an update | On macOS 27 direct builds, ⌘-drag them to the arrow's right; on earlier builds, drag them right of the separator |
| Login item missing after denying it once | System Settings > General > Login Items: re-enable Tuckaway, then toggle the pref off/on |
| A ghost "LauncherApplication" login item from old versions | Launch the current version once; it deauthorizes the legacy item automatically |
| App language stuck | See the `AppleLanguages` command above, or System Settings > General > Language & Region > Applications |
| Nothing hides on macOS 27 | Use the [direct-download build](https://github.com/Bruno-Alumn/Tuckaway/releases/latest) and grant **Device Control and Data Access**. The App Store build can't hide on macOS 27 and says so once. |
| Hiding stopped after an update | Expected once, when updating from 1.1.0 or earlier. In System Settings › Privacy & Security › Accessibility (Device Control and Data Access on macOS 27), remove Tuckaway with the − button, then open Tuckaway and allow it again |
| "Check for Updates" says it couldn't check | Check your internet connection. GitHub's API also limits anonymous requests per hour, so try again later. |
| A fast ⌘-drag springs back to where it started, or the bar stalls for a moment | macOS 27 behaviour; it happens with Tuckaway quit too. Drag steadily: press, pause briefly, then move. Or drag the icon in Settings › Menu Bar Items, and Tuckaway does the drag for you |
| A new or just-updated app's icon shows up already hidden | Expected, see "Why new icons start hidden" below; ⌘-drag it to the right of the separator (the arrow on macOS 27) once, or move it in Settings › Menu Bar Items |

### Why new icons start hidden

Tuckaway hides icons by widening its separator so everything to the *left* of
it slides off-screen. macOS always inserts a brand-new menu-bar icon at the
far-left slot, which is inside that hidden zone, so a freshly launched or updated
app can appear "swallowed". This is macOS positioning behavior, not Tuckaway
moving your icon: there is no way for one app to reposition another app's menu-bar
icon. The one-time fix is to ⌘-drag the icon to the right of the separator (the
arrow on macOS 27), or drag it to **Visible** in Settings › Menu Bar Items;
macOS remembers that placement per app.

## Requirements

macOS 13 Ventura or later, on Apple Silicon or Intel. For macOS 10.13–12, use
the original Hidden Bar
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10), the last release
on the old autostart mechanism.
