<div align="center">

<img src="img/icon_512%402x.png" width="128" height="128" alt="Tuckaway app icon">

# Tuckaway

**Tidy your Mac’s menu bar.**<br>
Choose what stays visible. Tuck away everything else.

<a href="https://github.com/Bruno-Alumn/Tuckaway/releases/latest"><img src="https://img.shields.io/badge/Download_for_macOS-7c3aed?style=for-the-badge&logo=apple&logoColor=white" alt="Download Tuckaway for macOS" height="40"></a>

<a href="https://github.com/Bruno-Alumn/Tuckaway/releases/latest"><img src="https://img.shields.io/github/v/release/Bruno-Alumn/Tuckaway?style=flat-square&color=7c3aed&label=release" alt="Latest release"></a>
<img src="https://img.shields.io/badge/macOS-13%2B-1f2937?style=flat-square&logo=apple&logoColor=white" alt="macOS 13 or later">
<img src="https://img.shields.io/badge/Swift-native-f05138?style=flat-square&logo=swift&logoColor=white" alt="Native Swift app">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2774c8?style=flat-square" alt="MIT license"></a>
<a href="#-built-with-ai"><img src="https://img.shields.io/badge/vibe_coded-%E2%9C%A8-ec4899?style=flat-square" alt="Vibe coded"></a>
<a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome_(AI_too)-22c55e?style=flat-square" alt="Pull requests welcome, AI-assisted included"></a>

<img src="img/tuckaway-menubar.gif" width="900" alt="Clicking Tuckaway’s arrow tucks away and reveals menu-bar icons">

<sub><a href="#-install">Install</a> &nbsp;·&nbsp; <a href="#-how-it-works">How it works</a> &nbsp;·&nbsp; <a href="#-features">Features</a> &nbsp;·&nbsp; <a href="#-privacy">Privacy</a> &nbsp;·&nbsp; <a href="#-contributing">Contributing</a></sub>

</div>

<br>

Tuckaway is a small, native macOS app that declutters your menu bar without
quitting the apps behind it. Arrange your icons once, then hide and reveal them
with a click, a shortcut, a hover, or a click on empty menu-bar space.

It's an independent, MIT-licensed fork of
[Hidden Bar](https://github.com/dwarvesf/hidden) that keeps working on
**macOS 27**, where the original's hiding trick stopped working.

## 📦 Install

1. Download **Tuckaway.dmg** from the [latest release](https://github.com/Bruno-Alumn/Tuckaway/releases/latest).
2. Open it and drag **Tuckaway** onto **Applications**.
3. Launch it and grant the [permissions](#-privacy) it asks for.

> [!TIP]
> If macOS says it can't verify the developer, open **System Settings ›
> Privacy & Security** and click **Open Anyway**. Releases are ad-hoc signed
> for now; notarization is planned.

Requires **macOS 13 Ventura or later** on Apple Silicon or Intel. Tuckaway then
**updates itself**: it checks GitHub once a day and offers **Install and
Relaunch** when a new version ships.

<details>
<summary><b>Coming from Hidden Bar?</b></summary>
<br>

Quit Hidden Bar first so the two apps don't fight over the menu bar. Tuckaway
imports your Hidden Bar settings once and never overwrites anything you change
afterwards.

</details>

## 🪄 How it works

Tuckaway adds an arrow to your menu bar. Everything to its **left** can be
tucked away; everything to its **right** always stays visible.

1. **Arrange:** hold <kbd>⌘</kbd> and drag icons to the left of the arrow to
   hide them, or move them in **Settings › Menu Bar Items**.
2. **Toggle:** click the arrow to tuck icons away or bring them back.
3. **Customize:** <kbd>Control</kbd>-click the arrow and choose **Settings…**
   (<kbd>⌘</kbd><kbd>,</kbd>).

| Do this | To |
|:--|:--|
| **Click** or **right-click** the arrow | Hide or show your icons |
| <kbd>⌘</kbd> **drag** an icon | Move it between the hidden and visible sides |
| <kbd>⌥</kbd> **click** the arrow | Show or hide the always-hidden section |
| <kbd>Control</kbd> **click** the arrow | Open the menu: Settings, updates, Quit |
| Your **global shortcut** | Hide or show from anywhere |

<p align="center">
  <img src="img/tuckaway-settings.gif" width="440" alt="Tuckaway Settings: General options, dragging an item between the Hidden and Visible lists, and About">
</p>

## ✨ Features

<table>
<tr>
<td width="33%" valign="top">

**🧹 One-click tidy**<br>
Hide and reveal the icons you choose, instantly.

</td>
<td width="33%" valign="top">

**⏱️ Tidies itself**<br>
Collapse again after a delay, or as soon as you switch apps.

</td>
<td width="33%" valign="top">

**🖱️ Reveal your way**<br>
Click, hover, a global shortcut, or a click on empty menu-bar space.

</td>
</tr>
<tr>
<td valign="top">

**🗂️ Drag-and-drop manager**<br>
Move icons between Hidden and Visible right from Settings.

</td>
<td valign="top">

**🔒 Always-hidden section**<br>
A second tier for icons you almost never need.

</td>
<td valign="top">

**📐 Notch-aware**<br>
Reach icons stuck behind the camera notch.

</td>
</tr>
<tr>
<td valign="top">

**🪟 Separate bar**<br>
Show hidden icons in a floating row you can click.

</td>
<td valign="top">

**🖥️ Display-aware**<br>
Optionally expand whenever an external display is connected.

</td>
<td valign="top">

**🔄 Built-in updates**<br>
Daily or on-demand, installed with one click.

</td>
</tr>
</table>

## 🔐 Privacy

No accounts, analytics, ads or tracking. The only network request is the update
check to GitHub, and you can turn it off. See the
[Privacy Policy](PRIVACY_POLICY.md).

| Permission | Why Tuckaway asks |
|:--|:--|
| **Accessibility**<br><sub>Device Control and Data Access on macOS 27</sub> | See where menu-bar icons are, detect empty menu-bar space, and pass clicks to hidden icons. |
| **Screen Recording** | Only for the separate bar, to show images of hidden icons. Nothing leaves your Mac. |

> [!NOTE]
> Releases are ad-hoc signed, so macOS may ask you to re-enable Accessibility
> after an update.

## 💜 Built with AI

Tuckaway is openly **vibe coded**. Much of it, including the Settings redesign
and the updater, was written in conversation with AI coding agents, then built,
tested and tried on a real menu bar before merging. What matters is whether a
change works, not how it was typed.

## 🤝 Contributing

**Everyone is welcome, and all uses of AI are allowed.** Whether this is your
first pull request or your thousandth, and whether you write Swift by hand, pair
with an AI, or let an agent do the whole thing, come on in.

- 🐛 **Found a bug or have an idea?** [Open an issue](https://github.com/Bruno-Alumn/Tuckaway/issues/new). Rough notes and screenshots are fine.
- 🔧 **Want to fix something?** Fork it and open a PR against `main`. Small fixes don't need an issue first.
- 🤖 **Not sure where to start?** Point your agent at [ARCHITECTURE.md](docs/ARCHITECTURE.md) and an open issue.

The [contributing guide](CONTRIBUTING.md) lists the only four requirements:
the change builds, the tests pass, you tried it on a real menu bar, and the PR
says what you checked.

<details>
<summary><b>Build from source</b></summary>
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

> [!IMPORTANT]
> Use the `-Direct` configurations. Plain `Debug`/`Release` build the sandboxed
> App Store variant, which can't hide icons on macOS 27.

</details>

<details>
<summary><b>Documentation</b></summary>
<br>

| | |
|:--|:--|
| [Manual](docs/MANUAL.md) | Every setting, shortcut and troubleshooting step |
| [Architecture](docs/ARCHITECTURE.md) | The two builds, both hiding engines, the updater, known limits |
| [Runbook](docs/RUNBOOK.md) | Verification and the release process |
| [Upstream issues](docs/UPSTREAM_ISSUES.md) | Hidden Bar issues fixed here, and what's still blocked |
| [Backlog](docs/BACKLOG.md) | What's open next |
| [Changelog](CHANGELOG.md) | What changed, release by release |

</details>

<br>

<div align="center">
<sub>
Built on <a href="https://github.com/dwarvesf/hidden">Hidden Bar</a> by <a href="https://github.com/dwarvesf">Dwarves Foundation</a> and its contributors. Not affiliated with or endorsed by them.<br>
<a href="LICENSE">MIT License</a> · Original work © 2019 Dwarves Foundation · Tuckaway modifications © 2026 Bruno-Alumn
</sub>
</div>
