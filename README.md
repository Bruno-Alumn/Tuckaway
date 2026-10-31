<div align="center">

<img src="img/icon_512%402x.png" width="136" height="136" alt="Tuckaway app icon">

# Tuckaway

**A quieter menu bar, on your terms.**

Hide the icons you don’t need, without quitting the apps behind them.

<a href="https://github.com/Bruno-Alumn/Tuckaway/releases/latest"><img src="https://img.shields.io/badge/Download_for_macOS-7c3aed?style=for-the-badge&logo=apple&logoColor=white" alt="Download Tuckaway for macOS" height="36"></a>

<a href="https://github.com/Bruno-Alumn/Tuckaway/releases/latest"><img src="https://img.shields.io/github/v/release/Bruno-Alumn/Tuckaway?style=flat-square&color=7c3aed&label=release" alt="Latest release"></a>
<img src="https://img.shields.io/badge/macOS-13%2B-1f2937?style=flat-square&logo=apple&logoColor=white" alt="macOS 13 or later">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2774c8?style=flat-square" alt="MIT license"></a>

[Install](#install) · [Using Tuckaway](#using-tuckaway) · [Features](#features) · [Privacy](#privacy) · [Contribute](#contribute)

</div>

---

Tuckaway puts a small arrow in your menu bar. Icons on its left are tucked out of
sight. Icons on its right stay exactly where they are. One click brings them all
back, so you can keep your workspace calm without losing the tools you rely on.

It’s an independent fork of [Hidden Bar](https://github.com/dwarvesf/hidden),
built to work with macOS 27’s new menu bar while retaining support for macOS 13
through 26.

<div align="center">
  <img src="img/tuckaway-menubar.gif" width="900" alt="Tuckaway’s arrow hiding and revealing menu-bar icons">
</div>

## Install

1. Download **Tuckaway.dmg** from the
   [latest release](https://github.com/Bruno-Alumn/Tuckaway/releases/latest).
2. Open the disk image and drag **Tuckaway.app** into **Applications**.
3. Launch it and grant the [permissions](#permissions) it requests.

Tuckaway runs on Apple Silicon and Intel Macs with macOS 13 or later. It checks
GitHub for updates once a day and can install new versions for you.

> **A note about signing:** releases aren’t notarized yet. macOS may show a
> warning on first launch. Review the release, then choose **Open Anyway** in
> System Settings › Privacy & Security if you’re comfortable installing it.
> Releases use the same certificate every time, so your permissions survive
> subsequent updates. Updating from 1.1.0 or earlier asks once more.

Switching from Hidden Bar? Quit it first so the two apps don’t compete for the
menu bar. Tuckaway copies your existing settings on its first run.

## Using Tuckaway

Arrange your icons once, then let Tuckaway do the tidying:

1. Hold <kbd>⌘</kbd> and drag icons to the left of the arrow to hide them.
   You can also move items between the Hidden and Visible lists in
   **Settings › Menu Bar Items**.
2. Click the arrow to collapse or expand.
3. Adjust how and when Tuckaway reveals icons in **Settings**.

| Action | What it does |
|:--|:--|
| Click or right-click the arrow | Hide or show your icons |
| <kbd>⌘</kbd>-drag an icon | Move it between sections |
| <kbd>⌥</kbd>-click the arrow | Hide or show the always-hidden section |
| <kbd>Control</kbd>-click the arrow | Open Settings, updates, and Quit |
| Your global shortcut | Hide or show from anywhere |

Settings has three tabs: **General**, **Menu Bar Items**, and **About**. You can
open it from the arrow’s menu or with <kbd>⌘</kbd><kbd>,</kbd>.

<div align="center">
  <img src="img/tuckaway-settings.gif" width="440" alt="Tuckaway’s General settings, item manager, and About screen">
</div>

## Features

**Automation that stays out of your way**

- Collapse after 5 seconds to a minute, or immediately when you switch apps.
- Reveal with a hover, a click on empty menu-bar space, or a global shortcut.
- Expand automatically when an external display is connected.

**Room for everything**

- Keep rarely used icons in a separate, always-hidden section.
- Find icons hidden behind a camera notch.
- Show hidden icons in a floating bar on macOS 13–26.

**A tool you can make your own**

- Choose a standard arrow, a transparent one, or an ellipsis.
- Reorder icons directly or through the Menu Bar Items manager.
- Launch quietly at login, with or without opening Settings.

## Privacy

Tuckaway has no accounts, analytics, or ads. Its only network request is the
daily update check to GitHub, which you can turn off in Settings. Everything
else stays on your Mac.

### Permissions

| Permission | Why it’s needed |
|:--|:--|
| **Accessibility** — called **Device Control and Data Access** on macOS 27 | Finds menu-bar icons, detects clicks on empty space, and forwards clicks to hidden items. |
| **Screen Recording** | Used only by the separate floating bar on macOS 13–26. Captured icons never leave your Mac. |

Read the full [Privacy Policy](PRIVACY_POLICY.md).

## Contribute

Tuckaway welcomes thoughtful fixes, small improvements, and new ideas. You don’t
need to ask before working on a small patch.

- **Found something broken?** [Open an issue](https://github.com/Bruno-Alumn/Tuckaway/issues/new)
  with rough notes or a screenshot.
- **Want to help?** Fork the repository and open a pull request against `main`.
- **Not sure where to begin?** [ARCHITECTURE.md](docs/ARCHITECTURE.md) explains
  the hiding engines, and [BACKLOG.md](docs/BACKLOG.md) lists open work.

AI-assisted contributions are welcome too. Much of Tuckaway was built with AI
coding agents, then compiled, tested, and exercised on a real menu bar before
merging. The standard is the same for every contribution: say what you changed
and be honest about what you tested.

Before opening a pull request, make sure it builds, the tests pass, and you’ve
tried it on a real menu bar. The [contributing guide](CONTRIBUTING.md) has the
commands.

<details>
<summary><strong>Build from source</strong></summary>
<br>

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

Use the **-Direct** configurations. Plain `Debug` and `Release` build the
sandboxed App Store variant, which can’t hide icons on macOS 27.

</details>

<details>
<summary><strong>Project documentation</strong></summary>
<br>

| Document | What’s inside |
|:--|:--|
| [Manual](docs/MANUAL.md) | Settings, shortcuts, permissions, and troubleshooting |
| [Architecture](docs/ARCHITECTURE.md) | Both build lanes and hiding engines, the updater, and known limits |
| [Runbook](docs/RUNBOOK.md) | Verification and release process |
| [Upstream issues](docs/UPSTREAM_ISSUES.md) | Hidden Bar issues addressed by Tuckaway |
| [Backlog](docs/BACKLOG.md) | Planned work and open design questions |
| [Changelog](CHANGELOG.md) | What changed in each release |

</details>

---

Tuckaway is based on [Hidden Bar](https://github.com/dwarvesf/hidden) by
[Dwarves Foundation](https://github.com/dwarvesf) and its contributors, and is
not affiliated with them.

**MIT License:** original work © 2019 Dwarves Foundation; Tuckaway changes ©
2026 Bruno-Alumn. See [LICENSE](LICENSE).
