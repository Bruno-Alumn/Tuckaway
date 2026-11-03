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

## New ideas

Suggested next, best first. Each says who has the problem, how it would work,
how big it is, and what could go wrong. Anything that needed a paid Developer ID,
a server, or collecting data was dropped.

1. **A rescue item for a menu bar that swallowed its own arrow.**
   - *Problem:* the arrow is Tuckaway's only UI. On macOS 13–26 it sits on the
     hidden side of a separator that is up to 10,000pt wide, and a narrow or
     over-full bar can put it off screen — the user's app is then invisible and
     unreachable, and the only cure is Terminal.
   - *Who:* crowded menu bars, large text, or a second display smaller than the
     main one. Same family as the self-repair that already exists
     (`StatusItemPositions`), but that only fixes saved positions.
   - *Use:* at launch and after each collapse, check the arrow's frame is on
     screen; if not, expand, repair, and show a small panel with **Repair Menu
     Bar**, **Open Settings** and **Quit Tuckaway** so the app can always be
     reached. Reset the separator's length if it can't be made to fit.
   - *Size:* S. The rescue path around `rescueArrowIfSwallowed` in
     `StatusBarController`, a panel modelled on `HiddenItemsBarPanelController`,
     `Assets` and the localization tables.
   - *Risks:* none for macOS 27 (no wide separator); a rescue panel is another
     always-on-top window, so it must be dismissed on any other interaction.
     Overlaps the existing `arrowRescueCount` path — it should extend it, not
     duplicate it.

2. **"Check Your Setup" in Settings.**
   - *Problem:* most support traffic is a missing permission or a bar that's
     arranged in a way Tuckaway can't hide with. Users can't tell which.
   - *Who:* anyone who grants Accessibility once and then revokes it, or who
     ⌘-drags icons into an order the engine can't use.
   - *Use:* a button under the Accessibility banner that runs the same checks
     Tuckaway runs at launch (permission, arrangement, screen-capture grant when
     the separate bar is on, login item) and lists what's wrong with a fix
     button for each.
   - *Size:* M. `PreferencesViewController` (new rows), a new pure
     `SetupDiagnosis` struct, `Util`/`MenuBarEngineFactory` for the inputs.
   - *Risks:* every check must be a public API call; no System Settings
     automation. Sandboxed build can run the permission and login-item checks
     only.

3. **Separators and spacers on macOS 27.**
   - *Problem:* macOS 27 has no separator, so the most-requested cosmetic
     (#299, #168) and the grouping spacers (#159) are half a feature there:
     spacers exist, but the `|` boundary people are used to doesn't.
   - *Who:* anyone coming from Hidden Bar, and anyone who grouped icons.
   - *Use:* on 27, draw the separator as a *spacer-like* item placed just left of
     the arrow while expanded (zero width while collapsed, like the spacers) so
     the bar looks the way it did before, and "Hide separators" hides it.
   - *Size:* M. `StatusBarController` (create/show loop it already does for
     spacers), `MenuBarSpacers` for the width maths, engine untouched.
   - *Risks:* the item has to stay out of the way while collapsed, which is the
     same rule spacers already follow; a purely visual item still costs a slot
     in a crowded bar.

4. **An "undo" for the new-app question.**
   - *Problem:* answering **Hide** for a new app once is permanent: the icon
     vanishes and the only way back is Menu Bar Items.
   - *Who:* someone who clicked Hide by reflex (Zoom, a helper app).
   - *Use:* after an answer, keep a small note in the separate bar's menu or the
     arrow's menu: **Undo: keep <App> hidden** for a few minutes.
   - *Size:* S. `StatusBarController` (`showNextNewAppPrompt` answer path,
     a menu item), `NewMenuBarAppTracker` needs nothing.
   - *Risks:* none beyond a little menu noise; it must disappear after a while
     rather than accumulate.

5. **Group always-hidden apps in Menu Bar Items by app, not by icon.**
   - *Problem:* on 27 hiding is per app (#427), but Menu Bar Items still lists
     each icon, so one app can appear in two lists and dragging one of them is
     misleading.
   - *Who:* apps with two icons (Dropbox, iStat) — the most common "it moved the
     wrong one" report.
   - *Use:* list one row per app in the Always Hidden/Hidden/Visible lists and say
     "2 icons" next to it.
   - *Size:* M. `MenuBarItemManagerWindowController` (scan and apply), pure
     grouping in a new `MenuBarItemGrouping` for tests.
   - *Risks:* 13–26 hiding is per icon (the separator pushes the whole area), so
     the grouping must only apply where the engine hides per app — otherwise the
     UI would claim something the old engine can't do.

6. **Show a hidden icon on click-through in the separate bar, instead of a
   synthetic click.**
   - *Problem:* the separate bar forwards a real click at captured coordinates;
     if the bar shifted since the capture, it can land on the wrong icon.
   - *Who:* anyone whose visible icons change width (timers, network meters).
   - *Use:* on 27, ask the owning app to open its menu through Accessibility
     (`AXShowMenu`) instead of clicking a position.
   - *Size:* M. `StatusBarController`'s native click path, `AccessibilityMenuBarInventory`.
   - *Risks:* not every app implements `AXShowMenu`; a fallback to the click is
     needed, which is more code than it replaces.

Dropped, with the reason:

- Reading which Focus mode is on (a profile per Focus): needs the Communication
  Notifications entitlement, i.e. a paid Developer ID — out of scope here.
- Per-icon hiding within one app (#427): macOS 27's restriction takes bundle
  identifiers; the OS blocks it.
- A "shown when inactive" group (#154): needs a restriction held while expanded,
  which drags assessment mode's side effects (Now Playing, Live Activities) into
  the expanded bar — worse than the problem.
- Noticing screen recording (#372) and picture-only icon changes (#229): no public
  signal, and hidden icons aren't drawn.
- A per-app "hide after N minutes" quieter mode: no one asked for it, and
  Tuckaway's own auto-collapse already covers the intent.
- A menu-bar layout export as a file (sharing profiles with coworkers): icon
  positions belong to macOS, so the file would promise more than it can restore.
- Widget/SwiftUI settings rewrite: cosmetic, large, and no user-visible gain.
- An option to hide macOS's own items (battery, Wi-Fi): the allow-list's system
  items are what keep the bar usable, and #437 already shows what happens when
  more of them go.

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
