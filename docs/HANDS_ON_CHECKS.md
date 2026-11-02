# Hands-on checks owed

Features that passed their unit tests and CI but haven't been used in the
running app yet. Work through this on a macOS 27 Mac before the next release,
and tick or fix each one. Remove an entry once it's been checked.

## Setup

Follow "When testing on a machine that runs Tuckaway daily" in
[RUNBOOK.md](RUNBOOK.md): quit the installed Tuckaway, export its settings by
file path, and run a `Debug-Direct` build:

```sh
xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway -configuration Debug-Direct \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
open build/DerivedData/Build/Products/Debug-Direct/Tuckaway.app
```

The ad-hoc build needs Accessibility granted again. Afterwards quit it, restore
the settings, reopen `/Applications/Tuckaway.app`, and put any moved icons back.

## From 1.8.0

- **Menu bar icon spacing:** pick Compact, then **Restart Menu Bar Apps…**:
  the confirmation names real apps, they quit and come back in the background,
  and their icons are closer together. Back to Default afterwards.
- **Profile shortcuts:** set one, press it (switches), press again (back to
  the arrow). A shortcut already used elsewhere is refused with a beep.

## Unreleased

- **Profile ⋯ menu:** Rename… (the shortcut still works under the new name;
  a taken name shows the alert), Use Current Layout, Remove App, Delete
  Profile… (asks first). The row lists the apps.
- **Schedule…:** set a window that starts in two minutes and ends two minutes
  later; the profile switches on, then back. Pick another profile inside the
  window and confirm it stays. Check the row shows the times.
- **Use While an App Is Open…:** choose an app, open it (switches), quit it
  (switches back). **Stop Following** removes it.
- **Show hidden icons briefly when they change:** with a hidden app whose icon
  shows text or changes width (a timer, a download count), wait for a change:
  it shows for about 8 seconds, then hides. An Always Hidden app never shows.
  Expanding and collapsing doesn't reveal anything by itself.
- **Show an app's hidden icon after it updates:** hard to trigger on demand;
  editing `knownAppVersions` in Tuckaway's defaults to an old version for a
  hidden app, then relaunching that app, simulates it. It shows for 30 seconds.
- **Spacers:** add two, ⌘-drag one between visible icons and one left of the
  arrow. Collapse: the left one shrinks to nothing; expand: it's back. Change
  the width; relaunch and confirm they stay where they were put.
- **Show how many icons are hidden:** collapse; the number next to the arrow
  matches the hidden icons and the arrow still clicks and right-clicks
  normally. Expand: the number goes away.
- **Collapse when the Mac locks or sleeps:** expand, lock the screen (⌃⌘Q),
  unlock: collapsed.
- **Expand across full menu bar caption:** reads well and doesn't crowd the
  Appearance section.

## macOS 13–26 only

Needs a Mac on 26 or earlier.

- **Clock date note (#207):** with the clock's Show Date on "When Space
  Allows", Settings › General shows the note; **Clock Options…** opens System
  Settings on the Control Center pane.
