# Changelog

## Unreleased

### Added
- **Find Hidden Icon** (macOS 27): from the arrow's menu or a shortcut you set in Settings › General, a small search lists your hidden icons by name. Type to filter, use the arrow keys, and press Return to open that icon's menu; it hides again when the menu closes. It needs no Screen Recording.

### Fixed
- Presentation Mode stopped hiding icons after an app launched, the Mac woke or a display changed, while still showing as on. It also showed every icon while a camera or microphone was in use, which is most screen shares; now it keeps hiding them (the dot in the screen corner still shows). Turning it on just as the bar collapsed could leave the arrow unresponsive until Tuckaway was restarted.
- After you answered **Hide** for a new app, its icon was hidden but missing from the separate hidden-items bar until something else made Tuckaway re-read the bar.
- A new-app question left on screen could undo a choice made meanwhile in Menu Bar Items or the separate bar's menu; it now closes when the app is decided elsewhere. Menu Bar Items lists undecided apps under Visible, since they're showing.
- If an app launched or the Mac woke while the separate bar was opening, a still picture of the menu bar could stay over the real one.
- On macOS 27, dragging an icon into **Visible** in Menu Bar Items now keeps that app visible, as **Keep Visible** does. Before, Tuckaway tried to ⌘-drag the icon past its own arrow, which macOS 27 doesn't allow, so the icon stayed hidden.
- In the separate hidden-items bar, macOS's own menu bar extras are named by what they are (for example "Siri"), as in Menu Bar Items, instead of "SystemUIServer".

## v1.6.1 (2026-11-02)

### Fixed
- After **Install and Relaunch**, Tuckaway sometimes installed the update but didn't reopen, so it looked like it had quit. It now keeps trying to reopen until it's running. This applies to updates installed from this version on.

## v1.6.0 (2026-11-02)

### Added
- **Presentation Mode** (macOS 27): hides every app's menu bar icon, including the ones you keep visible, so screen shares and recordings show a clean menu bar. macOS's own items (clock, Wi-Fi, battery, Control Center) and Tuckaway's arrow stay. Turn it on from the arrow's menu or with a shortcut you set in Settings › General; click the arrow to turn it off.

## v1.5.0 (2026-11-02)

### Added
- With "Hover to expand" on, hovering over the menu bar opens the separate hidden-items bar instead of expanding, and it closes again shortly after the pointer leaves it.
- The separate bar shows an app's name when you point at its icon, and VoiceOver reads each icon as a button named after its app.
- Right-click an icon in the separate bar for **Keep Visible** (macOS 27), which keeps that app showing in the menu bar, and **Manage Menu Bar Items…**.

## v1.4.1 (2026-11-02)

### Added
- On macOS 27, a newly installed app's menu bar icon no longer disappears straight away. macOS puts new icons on the hidden side, so Tuckaway keeps the icon showing and asks, under the arrow, whether to keep it visible. **Keep Visible** keeps that app showing wherever its icon sits, and Menu Bar Items lists it under Visible; drag it to Hidden there to change your mind. **Hide** hides it as usual. Apps that were already in your menu bar aren't asked about.

## v1.4.0 (2026-11-02)

### Added
- "Show hidden items in separate bar" works on macOS 27. Clicking the arrow shows the hidden icons in a row under the menu bar while the bar stays collapsed, and clicking one opens it as usual; it hides again once its menu closes. It needs Screen Recording and Accessibility, as before.

### Fixed
- After the separate bar closed, the arrow kept its expanded look even though the icons were hidden.

## v1.3.1 (2026-11-01)

### Fixed
- On macOS 27, 1.3.0 couldn't install updates: every attempt said the download "didn't contain a valid copy of Tuckaway". It was looking for a system tool in the wrong folder.

## v1.3.0 (2026-11-01)

### Added
- Menu Bar Items has an **Always Hidden** list when the always-hidden section is on, so you can see those icons and drag icons into or out of that section. Before, they were mixed into Hidden and couldn't be moved there. While the tab is open, Tuckaway shows that section and holds off auto-collapse, then puts both back when you close it.

### Fixed
- Tuckaway could crash, or put an icon in the wrong list, if macOS answered an Accessibility query with an unexpected kind of value while reading the menu bar, the notch or the clock. It now ignores such answers.
- On a Mac with a notch, when macOS doesn't report where the notch is, "Show Notch Items" now assumes it's in the middle of the screen. It used a fixed position that only suited one screen size. Its fallback app name "Unknown" is also localized instead of always appearing in English.
- On macOS 27, icons hide a few seconds sooner after launch. Tuckaway was waiting for a divider that macOS 27 doesn't use.
- Dropping an icon next to itself in Menu Bar Items can no longer crash Tuckaway.
- If the Mac's clock was set back, automatic update checks stopped until the clock caught up again. They now carry on.
- The update alert no longer drops the # from an issue number such as #437 at the start of a line.
- Shortcut recording no longer accepts Shift by itself, and invalid shortcuts saved by older versions are ignored at launch, so something like Shift+A can't make ordinary capitalized typing toggle the menu bar. Shift still works alongside Command, Control or Option.
- Update checks now bypass the local URL cache, so checking manually can't offer an older release because GitHub's previous response was cached.
- If an update fails and restoring the previous app also fails, the updater now keeps that backup instead of deleting the only remaining copy.
- The updater now rejects truncated or oversized downloads before unpacking them by checking their byte count against GitHub's release metadata.
- With more than one display, "Show hidden items in separate bar" captured and clicked the wrong spot whenever a display of a different height had keyboard focus, and the "Show Notch Items" menu only appeared while the built-in display had focus. Both now use the right screen.
- The notch overflow menu ("Show Notch Items") could freeze Tuckaway for seconds while it opened, because it asked every running process, helpers included, one at a time. It now asks only apps, all at once, with a short timeout: 17 ms instead of 3.1 s on a cold first open.
- On macOS 27, launching any app, waking the Mac or changing displays showed every hidden icon, and they stayed visible until you clicked the arrow. Tuckaway now hides them again about two seconds after things settle. It waits while your pointer is in the menu bar, and doesn't re-hide if "Expand with an external display" is keeping the bar open.
- On the very first launch, auto-collapse didn't start, and after migrating from Hidden Bar the always-hidden separator was missing until a relaunch. Tuckaway was reading your settings before loading them.
- The app icon had solid black corners: the artwork was drawn on an opaque black square, so black showed in Finder, the Dock, ⌘-Tab, the About window, alerts and the README. It's now cut out with transparent corners and sits on Apple's icon grid (an 824-point rounded square on a 1024 canvas, with the standard shadow), so it's no longer oversized next to other apps.

### Changed
- Menu Bar Items and the icon mover no longer stall when one app stops responding: they ask all apps at once and give each a quarter of a second.
- The update alert shows what changed, as readable text. It used to show the first 600 characters of the raw release notes: Markdown symbols, plus download-and-install instructions that make no sense inside the updater.
- Settings no longer pops up every time Tuckaway starts, such as at login or after each update. It opens on the very first launch, and "Open settings on launch" (now off by default) brings back the old behaviour.
- VoiceOver now reads Tuckaway's arrow as "Show hidden icons" or "Hide icons", depending on what a click will do. Before, it had no label at all. Hovering the arrow shows a "Tuckaway" tooltip.
- "Show hidden items in separate bar" is hidden on macOS 27, where it couldn't work: macOS 27 no longer gives menu-bar icons their own windows, so there was nothing to capture, and every click flashed a cover and then just expanded the bar. It still works on macOS 13–26.
- Tuckaway is fully translated again in all 13 languages (Arabic, Chinese (Simplified and Traditional), Croatian, French, German, Italian, Japanese, Polish, Turkish, Ukrainian, Vietnamese). The new Settings, Menu Bar Items, About and updater screens were English-only, and some languages had only a handful of strings. A test now fails if a string is missing from any language.
- On macOS 27, the updater and `scripts/package-dmg.sh` use `diskutil image` instead of the deprecated `hdiutil`, which stays on macOS 13–26. "Open Accessibility Settings" uses macOS 27's new Settings link.

## v1.2.0 (2026-10-30)

### Fixed
- ⌘-pressing Tuckaway's arrow (or separator) while arranging icons collapsed or expanded the bar, or opened the menu. By macOS convention a ⌘-press on a menu-bar icon starts arranging, so it now does nothing; plain clicks and VoiceOver presses are unchanged.
- ⌘-dragging icons in the menu bar could stutter and misbehave. If your hand drifted below the menu bar mid-drag, auto-collapse saw the pointer "leave" and collapsed the bar under the drag. Auto-collapse, hover-to-expand and collapse-on-app-switch now wait until no mouse button is held.
- Updater: each update left its download and unpacked copy (about 4 MB) in the temporary folder. The whole work folder is now deleted after installing, and as soon as an update fails.

### Changed
- Releases are signed with a single certificate, "Tuckaway Release Signing", instead of a different ad-hoc signature each time. macOS now keeps Tuckaway's Accessibility and Screen Recording permissions, and firewall rules, across updates. Updating from 1.1.0 or earlier asks once more.
- The updater only installs an update signed with the same certificate as the running copy, so a tampered or differently signed download is refused.
- Release builds no longer carry the debug-only `get-task-allow` entitlement.

## v1.1.0 (2026-10-30)

### Added
- Releases ship as a disk image, `Tuckaway.dmg`, instead of a zip. `scripts/package-dmg.sh` builds it from `Release-Direct` (universal) and refuses Debug or sandboxed builds. The updater installs from the DMG and still accepts zips, so v1.0.0 can update.
- Built-in updater (direct-download build). It checks GitHub releases once a day, or on demand from Settings › General › Updates, About, or the arrow's menu. It offers Install and Relaunch, Later, or Skip This Version. Installs are verified (bundle ID, version, code signature) before the app is swapped, with automatic rollback on failure.

### Changed
- Documentation rewritten for Tuckaway as it is now: the manual covers the Settings window, Menu Bar Items and updates; the architecture covers both builds, both hiding engines and the updater; the runbook, backlog and upstream-issue status drop Hidden Bar–era instructions and stale PR numbers.
- Redesigned Settings: a smaller 480pt window with standard toolbar tabs (General, Menu Bar Items, About) that resizes to each tab.
- General is now a grouped form ordered by intent — Hiding, Revealing, Appearance, Extra Sections, Startup. The collapse delay only appears while auto-collapse is on, and the always-hidden help is an inline footer instead of a popover.
- Menu Bar Items uses lighter inset lists with section icons, item counts, a "Drop items here" hint on empty lists, and a compact footer.
- About is a compact centered card.
- The arrow's context menu: "Auto-collapse" is a checkmark item, "Settings…" uses ⌘, , "Manage Menu Bar Items…" opens that tab directly, and Quit reads "Quit Tuckaway".

### Fixed
- Menu Bar Items: dragging an item no longer flings the cursor onto the menu bar, and the item lands where you drop it instead of at the end of the list. The list updates the moment you drop. The real menu bar follows in about half a second with the cursor hidden and left where it was, and the list corrects itself if macOS puts the item somewhere else.
- Menu Bar Items: moving an item could leave macOS thinking ⌘ was still held down afterwards, which broke the next move and made ordinary typing act like ⌘ shortcuts.
- macOS 27: the App Store build's notice said menu-bar hiding was impossible on macOS 27, although the direct-download build supports it. The notice now says only that version can't hide icons, and links to the direct download instead of the upstream issue.

## v1.0.0 (2026-10-30)

### Fixed
- Preferences uses a native settings toolbar and compact controls; General and About keep the same width.
- Shortcut recording cancels when the window closes, loses focus, or changes tabs. Invalid typing preserves the saved shortcut.
- Always-hidden help now describes the correct boundary and Option-click behavior for the active engine.
- macOS 27: without the Accessibility permission, clicking the arrow silently did nothing. Preferences now shows a banner with an "Open Settings…" button while the permission is missing, clicking the arrow opens Preferences instead of doing nothing, and hiding starts as soon as the permission is granted, without a relaunch.
- macOS 26+: the menu-bar illustration in Preferences sat under the taller toolbar; it is now laid out below it.
- macOS 27: the Preferences illustration no longer shows a separator that the native hiding takes out of the bar, and points at the arrow, which is the boundary there.
- macOS 27 (direct download build): while any app uses the microphone or a camera, Tuckaway stops hiding and shows the whole bar, then resumes when that stops. macOS 27's native hiding hides the menu-bar capsule that names the recording app (#437); the dot in the screen corner stays visible.
- macOS 27 (direct download build): clicking the clock opens Notification Center again while icons are hidden (#410, #421, #435). Tuckaway briefly lifts hiding and presses the clock; hidden icons show for under a second. This also covers the expanded bar when the always-hidden section is hidden.

### Known / in progress
- macOS 27 (direct download build): native hiding is part of macOS's exam (assessment) mode, and macOS applies that mode's other restrictions while the arrow is collapsed (#437). Now Playing and Live Activities are hidden; the manual lists the details.

### Changed
- Rebranded the independent fork as Tuckaway, with a new icon, bundle identity, documentation, and one-time Hidden Bar preference migration.
- Manual: macOS's own items that stay visible while collapsed on macOS 27 are the clock, Control Center, Wi-Fi, Bluetooth, Sound, Battery, Display, Keyboard and Screen Mirroring, not all of them as previously stated.

## v1.11.1 (2026-09-18)

### Fixed
- macOS 27: the Preferences window showed a "Custom View" placeholder instead of the General/About tabs, and the label overlapped the window once clicked (#406).

## v1.11 (2026-09-18)

Requires macOS 13 Ventura or later. (Pre-Ventura users: stay on
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10).)

### Added
- Opt-in hover-to-expand: set `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true` to expand the bar when the pointer dwells in the menu bar.
- Right-clicking the expand/collapse arrow now opens the same context menu as the separator, so Preferences is reachable from the control you already click.

### Fixed
- macOS 27 (direct download build): hiding works again (#360) using macOS 27's native menu-bar visibility instead of widening the separator, which macOS 27 ejects from the bar. The arrow is the boundary: icons ⌘-dragged to its left hide when collapsed. Needs the Accessibility permission, and Hidden Bar must run from /Applications. Hiding is per app, and macOS's own items always stay visible. The App Store build is unchanged for now.
- Enabling the always-hidden section at runtime no longer creates an invisible (0pt) separator.
- Multi-display: the collapse width is now sized for the widest attached screen, so icons no longer leak on wider external monitors; the width re-applies on display hot-plug.
- Auto-collapse no longer fires while you are interacting with the menu bar (the timer defers and re-arms while the pointer is in the bar).
- The Preferences window no longer closes when auto-collapse fires with "use full menu bar on expanding" enabled (#170, #66, #151).
- Status items that were dragged off the bar are restored at launch instead of leaving the app unreachable.
- Fixed constraint and observer leaks in the tutorial view rebuild.
- Tutorial strings and F-key shortcut labels now render correctly (no more private-use glyphs).

### Changed
- Start-at-login now uses `SMAppService` (macOS 13+); the legacy launcher helper was removed and any leftover login item is deauthorized automatically on first launch.
- Pinned the HotKey dependency to an exact version and removed an unused file-access entitlement and dead code (no behavior change).

### Known / in progress
- macOS 27, App Store build: hiding still does not work (#360). Native hiding needs Accessibility reads that the App Sandbox blocks; an App Store approach is tracked separately.
- New menu-bar icons can appear in the hidden zone because macOS inserts them at the far left; ⌘-drag them to the right of the separator (see the manual). A built-in pin is part of the planned redesign.
