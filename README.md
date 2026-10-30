<p align="center">
  <img src="img/icon_512%402x.png" width="168" height="168" alt="Tuckaway app icon">
</p>

<h1 align="center">Tuckaway</h1>

<p align="center">
  <strong>Tidy your Mac’s menu bar.</strong><br>
  Choose what stays visible. Tuck away everything else.
</p>

<p align="center">
  <a href="https://github.com/Bruno-Alumn/Tuckaway/releases/latest"><img src="https://img.shields.io/github/v/release/Bruno-Alumn/Tuckaway?color=7c3aed&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-1f2937" alt="macOS 13 or later">
  <img src="https://img.shields.io/badge/Swift-native-ef5b45" alt="Native Swift app">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2774c8" alt="MIT license"></a>
  <a href="#built-with-ai"><img src="https://img.shields.io/badge/vibe%20coded-%E2%9C%A8-ff69b4" alt="Vibe coded"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome%20(AI%20too)-22c55e" alt="Pull requests welcome, AI-assisted included"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#features">Features</a> ·
  <a href="#privacy--permissions">Privacy</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="#contributing">Contribute</a>
</p>

---

<p align="center">
  <img src="img/tuckaway-menubar.gif" width="900" alt="Clicking Tuckaway’s arrow tucks away and reveals menu-bar icons">
</p>

Tuckaway is a small, native macOS app for decluttering the menu bar without
quitting the apps behind it. Arrange your icons once, then hide and reveal them
with a click, a keyboard shortcut, a hover, or a click on empty menu-bar space.

It's an independent, MIT-licensed fork of
[Hidden Bar](https://github.com/dwarvesf/hidden) that keeps working on
**macOS 27**, where the original's hiding trick no longer works. It is not
affiliated with or endorsed by Hidden Bar's maintainers.

## Install

1. Download **Tuckaway.zip** from the
   [latest release](https://github.com/Bruno-Alumn/Tuckaway/releases/latest).
2. Unzip it and drag **Tuckaway.app** into **Applications**.
3. Open it. If macOS says it can't verify the developer, go to
   **System Settings › Privacy & Security** and choose **Open Anyway**.
   Releases are ad-hoc signed for now; notarization is planned.
4. Grant the [permissions](#privacy--permissions) it asks for.

Requires **macOS 13 Ventura or later**, on Apple Silicon or Intel.

From then on, Tuckaway **updates itself**: it checks GitHub once a day and
offers **Install and Relaunch** when a new version ships. You can also choose
**Check for Updates…** from the arrow's menu, or turn automatic checks off in
Settings.

> **Coming from Hidden Bar?** Quit Hidden Bar first so the two apps don't fight
> over the menu bar. Tuckaway imports your Hidden Bar settings once and never
> overwrites anything you change afterwards.

## Quick start

1. **Arrange:** hold **⌘** and drag menu-bar icons to the left of Tuckaway's
   arrow to hide them. Icons to its right stay visible.
2. **Toggle:** click the arrow (or right-click it) to tuck icons away or bring
   them back.
3. **Customize:** **Control-click** the arrow and choose **Settings…** (⌘,).
   - **General** groups options by what they do: Hiding, Revealing, Appearance,
     Extra Sections, Startup and Updates.
   - **Menu Bar Items** lets you drag icons between Hidden and Visible instead
     of ⌘-dragging in the menu bar.
4. **Go further:** turn on the always-hidden section for icons you almost never
   need, then **Option-click** the arrow to show or hide it.

<p align="center">
  <img src="img/tuckaway-settings.gif" width="560" alt="Tuckaway Settings: General options, dragging an item between the Hidden and Visible lists, and About">
</p>

## Features

| | |
|---|---|
| **One-click tidy** | Hide and reveal chosen menu-bar icons instantly. |
| **Hides itself again** | Auto-collapse after a delay, or as soon as you switch apps. |
| **Reveal your way** | Click, right-click, hover, a global shortcut, or a click on empty menu-bar space. |
| **Drag-and-drop manager** | Move icons between Hidden and Visible from Settings. |
| **Always-hidden section** | A second tier for icons you rarely need. |
| **Notch overflow** | Reach icons stuck behind the camera notch. |
| **Separate hidden-items bar** | Show hidden icons in a floating row you can click. |
| **Display-aware** | Optionally expand when an external display is connected. |
| **Your look** | Standard, transparent, or ellipsis arrow. |
| **Built-in updates** | Daily or on-demand checks against GitHub releases, installed with one click. |
| **macOS 27 ready** | Uses macOS 27's native menu-bar hiding in the direct-download build. |

## Privacy & permissions

| Permission | Why |
|---|---|
| **Accessibility** (called **Device Control and Data Access** on macOS 27) | Read where menu-bar icons are, detect empty menu-bar space, and pass clicks to hidden icons. |
| **Screen Recording** | Only for the separate hidden-items bar, to show images of hidden icons. Nothing leaves your Mac. |

Tuckaway has **no accounts, analytics, ads or tracking**. Its only network
request is the update check to GitHub, which you can turn off. Details are in
the [Privacy Policy](PRIVACY_POLICY.md).

Because releases are ad-hoc signed, macOS may ask you to re-enable Accessibility
after an update.

## Build from source

You need a current Xcode.

```sh
git clone https://github.com/Bruno-Alumn/Tuckaway.git
cd Tuckaway
xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway \
  -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO build
```

Run the tests:

```sh
xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway \
  -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO test
```

> **Use the `-Direct` configurations** (`Debug-Direct`, `Release-Direct`).
> Plain `Debug`/`Release` produce the sandboxed App Store variant, which can't
> hide icons on macOS 27 and shows a warning saying so.

Each local build has a new signature, so macOS may ask for permissions again.

## Built with AI

Tuckaway is openly **vibe coded**. Much of it, including the current Settings
redesign and the updater, was written in conversation with AI coding agents,
then built, tested and tried on a real menu bar before merging.

We think that's a great way to build software, and you're welcome to work the
same way. What matters is whether the change works, not how it was typed.

## Contributing

**Everyone is welcome.** It doesn't matter if this is your first pull request or
your thousandth, or whether you write Swift by hand, pair with an AI, or let an
agent do the whole thing. **All uses of AI are allowed.**

- **Found a bug or have an idea?**
  [Open an issue](https://github.com/Bruno-Alumn/Tuckaway/issues/new). Rough
  notes and screenshots are fine.
- **Want to fix something?** Fork, make the change, and open a PR against
  `main`. Small fixes don't need an issue first.
- **Not sure where to start?** Point your AI agent at
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and an open issue, and go.

The [contributing guide](CONTRIBUTING.md) covers the few things we ask: build it,
run the tests, try it on a real menu bar, and say what you checked.

## Documentation

- [Manual](docs/MANUAL.md): every setting, permission, and troubleshooting step
- [Architecture](docs/ARCHITECTURE.md): how hiding works, the engines, known limits
- [Maintainer runbook](docs/RUNBOOK.md): verification and release process
- [Upstream issue status](docs/UPSTREAM_ISSUES.md): Hidden Bar issues fixed here, and what's still blocked
- [Changelog](CHANGELOG.md)

## Acknowledgments

Tuckaway stands on Hidden Bar by [Dwarves Foundation](https://github.com/dwarvesf)
and the many people who contributed to it. Upstream issues and pull requests
folded into Tuckaway are tracked in [docs/UPSTREAM_ISSUES.md](docs/UPSTREAM_ISSUES.md).

## License

[MIT](LICENSE). Original work © 2019 Dwarves Foundation; Tuckaway modifications
© 2026 Bruno-Alumn. Provided “as is,” without warranty of any kind.
