# Profiles (design draft)

Status: built (macOS 27) with these defaults for the **Decide** points, which
the owner can still change: a profile only affects the collapsed bar; Settings
only holds the profiles' shortcuts (no rename or editing yet); Keep Visible adds
the app to the active profile. Not built yet: switching by Focus or time.
Switching on a display connection and a shortcut per profile are built. The engine took a narrower route than `setVisibleOverride`:
`ProfileApplying.setProfile` feeds the effective layout, and presentation mode
stays separate and wins.

## What it's for

People rearrange the menu bar for a context: work, presenting, a quiet evening.
Today that means ⌘-dragging icons each time, or Menu Bar Items. A profile is a
named set of apps that stay visible, switched in one step.

## How it fits macOS 27

On macOS 27 Tuckaway hides by handing MenuBarAgent a list of apps to keep
visible (`NativeVisibilityEngine.activate(allowing:)`). Sections are just how
that list is chosen: everything right of the arrow, plus kept and undecided
apps. Presentation mode (1.6.0) already overrides the list with an empty one.

A profile is the same override with a saved list. So the engine change is to
generalize presentation mode:

```swift
// nil: the sections decide (today's behaviour).
// []: presentation mode.
// [bundles]: a profile.
func setVisibleOverride(_ bundles: [String]?)
```

`isPresenting` becomes `override == []`, and the robustness fixes from #96
(layout changes, a collapse in flight, camera or microphone in use) carry over
unchanged, because they're about holding an override rather than about it
being empty.

Expanded still shows everything, as with presentation mode today: a profile
only changes what the **collapsed** bar shows. **Decide:** or should a profile
also stay in force while expanded, like presentation mode does?

## Where it lives

- **Arrow's menu:** a Profiles submenu: "Use the Arrow" (no profile), one item
  per profile with a checkmark on the active one, then "Save Current Layout as
  Profile…" and "Delete Profile" (submenu).
- **Saving** takes what the collapsed bar shows right now: the visible section
  plus kept and undecided apps. A small alert asks for the name.
- **Settings › General:** nothing at first. **Decide:** add a Profiles section
  later (rename, edit the list, a shortcut per profile)?
- **Stored** in defaults as `profiles: [name: [bundle id]]` and
  `activeProfile: name?`. The active profile survives relaunch; presentation
  mode doesn't (as today).

## Interactions

- **New apps.** An app that isn't in the active profile is hidden. The new-app
  question still appears; Keep Visible then adds the app to the active
  profile. **Decide:** or to the arrow's layout only?
- **Menu Bar Items** shows the arrow's layout, not the profile. While a profile
  is active, it shows a note ("Profile Work is active; the menu bar shows its
  apps") and moves still edit the layout.
- **Presentation mode** wins over a profile while it's on, then the profile
  comes back.
- **Separate bar and Find Hidden Icon** list what the profile hides: every
  running app with an icon that isn't in the profile.
- **macOS 13–26:** not offered. The legacy engine hides by position only.

## Later

- Switch automatically: when a display is connected, on a Focus mode
  (`NSWorkspace`/`INFocusStatusCenter`), or by time of day.

## Testing plan

Engine tests with the existing fakes: an override replaces the list, survives
`invalidateLayout`, waits for a collapse in flight, and holds while a camera is
on; clearing it re-applies the state. A model test for saving (visible + kept +
pending) and for adding a kept app to the active profile. On hardware: save two
profiles with different apps, switch between them collapsed and expanded, and
relaunch with one active.
