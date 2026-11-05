# Hands-on checks owed

Features that passed their unit tests and CI but haven't been used in the
running app yet. Work through this on a macOS 27 Mac before the next release,
and tick or fix each one. Remove an entry once it's been checked.

## Setup

Follow "When testing on a machine that runs Tuckaway daily" in
[RUNBOOK.md](RUNBOOK.md): quit the installed Tuckaway, export its settings by
file path, and run a `Release-Direct` build signed with the release identity,
so the installed app's Accessibility grant applies (a Debug build's separate
debug dylib won't load once re-signed):

```sh
xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway -configuration Release-Direct \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
codesign --force --deep --options runtime --entitlements hidden/Hidden-Direct.entitlements \
  --sign "Tuckaway Release Signing" build/DerivedData/Build/Products/Release-Direct/Tuckaway.app
open build/DerivedData/Build/Products/Release-Direct/Tuckaway.app
```

Afterwards quit it, restore the settings, reopen `/Applications/Tuckaway.app`,
and put any moved icons back. Things learned on 2026-11-03 (macOS 27.2):

- Run from the build folder, the arrow isn't drawn while collapsed (macOS
  only honours the allow-list for an app in /Applications). Read its state
  and title through Accessibility instead, or expand first.
- Moving an icon to **Visible** in Menu Bar Items marks the app kept visible
  unless **Allow Moving Icons…** has been granted (#165), so note the bar's
  order before testing and check `keptVisibleMenuBarApps` when restoring.

Things learned on 2026-11-05 in a macOS 27.2 VM (terminal-mac):
- Install the build in the VM's /Applications so the arrow is drawn while
  collapsed, and start it from a Terminal that has Accessibility, so a new
  build needs no new grant.
- ⌘-drags posted as HID events from a tool run in that Terminal do register;
  a Control-click (to open the arrow's menu) can be posted the same way.
- Restoring settings doesn't restore icon positions: macOS keeps those. Adding
  a spacer shifted the installed app's arrow one place to the right
  afterwards.

## From 1.8.0

- **Menu bar icon spacing:** pick Compact, then **Restart Menu Bar Apps…**:
  the confirmation names real apps, they quit and come back in the background,
  and their icons are closer together. Back to Default afterwards.
- **Profile shortcuts** (checked 2026-11-05 in the VM: ⌃⌥⌘N, posted as HID
  key events, switched to the profile and back). Still to check: a shortcut
  already used elsewhere is refused with a beep.

## Unreleased

- **Undo a new-app answer** (the question itself was checked 2026-11-03 by
  removing an app from `knownMenuBarApps`): install or relaunch an app that
  wasn't in the menu bar before, answer **Hide** on its question, then Control-click the arrow
  within five minutes: **Undo: keep <app> visible** is there and its icon comes
  back. Answer a second app with **Keep Visible** and the menu offers **Undo:
  hide <app>**. The item is gone after five minutes.
- **Check Your Setup** (checked 2026-11-03: "collapsing hides nothing" with
  no hidden icons, "Everything looks right." with one, the picture and caption
  still above it). Still to check: revoke Accessibility and it lists only that
  (no button); separate bar on with Screen Recording off; **Menu Bar Items…**
  and the App Store build on 27.
- **What's New** (checked 2026-11-03: 1.8.0's notes shown once, version
  recorded, **Done** closes it; 2026-11-05 in the VM: with `hasLaunchedBefore`
  deleted, Settings opens and What's New doesn't).
- **Profile ⋯ menu** (checked 2026-11-05 in the VM: Rename…, Use Current
  Layout, Remove App, Delete Profile… asks first, the row lists the apps;
  that pass found Dock and WindowManager listed, fixed in #170; the shortcut
  still works under the new name, and a taken name shows "A profile named
  “Late” already exists.").
- **Schedule…** (checked 2026-11-05 in the VM: a 00:52–00:54 window switched
  the profile on within 3 s of 00:52 and back to the arrow within 4 s of
  00:54; the row shows "00:52 – 00:54"). Still to check: pick another
  profile inside the window and confirm it stays.
- **Show hidden icons briefly when they change:** with a hidden app whose icon
  shows text or changes width (a timer, a download count), wait for a change:
  it shows for about 8 seconds, then hides. An Always Hidden app never shows.
  Expanding and collapsing doesn't reveal anything by itself.
- **Show an app's hidden icon after it updates:** hard to trigger on demand;
  editing `knownAppVersions` in Tuckaway's defaults to an old version for a
  hidden app, then relaunching that app, simulates it. It shows for 30 seconds.
- **Spacers** (checked 2026-11-03: one left of the arrow is 2 pt collapsed and
  18 pt expanded). Still to check: one ⌘-dragged between visible icons keeps
  its width; a width change; positions survive a relaunch.
- **Show how many icons are hidden** (checked 2026-11-03: **1** with one hidden
  icon, gone when expanded). Still to check, from /Applications: the arrow
  still clicks and right-clicks normally with the number showing.
- **Collapse when the Mac locks or sleeps:** expand, lock the screen (⌃⌘Q),
  unlock: collapsed.
- **Expand across full menu bar caption:** reads well and doesn't crowd the
  Appearance section.

## macOS 13–26 only

Needs a Mac on 26 or earlier.

- **Arrow rescue notice**: ⌘-drag the arrow to the far left of the
  bar, past the separator, collapse, and relaunch — the first repair puts it
  back. To reach the notice itself, repeat it within the same run until the
  repair limit is hit: the panel appears under the menu bar (on the main
  display, since the arrow has none) and **Repair Menu Bar** clears it. Do it
  again and press **Later** (or Esc): the panel closes and doesn't come back
  on the next collapse.
- **Clock date note (#207):** with the clock's Show Date on "When Space
  Allows", Settings › General shows the note; **Clock Options…** opens System
  Settings on the Control Center pane.
