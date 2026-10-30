<p align="center">
  <img width="180" height="180" src="img/icon_512%402x.png" alt="Tuckaway app icon">
</p>

# Tuckaway

**Tidy your Mac’s menu bar.**

Tuckaway lets you choose which menu-bar icons stay visible and which are tucked
out of sight. It is a native macOS utility with automatic collapse, global
shortcuts, an always-hidden section, notch overflow, and a separate hidden-items
bar.

Tuckaway is an independent, MIT-licensed fork of
[Hidden Bar](https://github.com/dwarvesf/hidden), maintained by
[Bruno-Alumn](https://github.com/Bruno-Alumn). It is not affiliated with or
endorsed by the Hidden Bar maintainers.

## Highlights

- Click the arrow to collapse or expand your chosen icons.
- Auto-collapse after a configurable delay, on app switch, or expand with hover.
- Keep frequently used icons visible with ⌘-drag arrangement or the item manager.
- Use an always-hidden section for icons you rarely need.
- Show hidden items in a separate bar, including icons behind a camera notch.
- Choose standard, transparent, or ellipsis expand icons.
- Toggle from empty menu-bar space or with a global keyboard shortcut.
- Optionally expand automatically when an external display is connected.
- Launch at login without opening Preferences.

## Requirements

- macOS 13 Ventura or later
- Intel or Apple Silicon Mac

macOS 27 uses a different native hiding engine. It requires the direct,
non-sandboxed build and **Device Control and Data Access** permission (the
Accessibility permission under macOS 27's updated Settings wording).

## Install

Download Tuckaway from the
[project’s releases](https://github.com/Bruno-Alumn/hidden/releases), move
**Tuckaway.app** to `/Applications`, and launch it.

If you are upgrading from Hidden Bar, Tuckaway copies your existing preferences
once without overwriting preferences you subsequently change in Tuckaway. macOS
treats Tuckaway as a separate app, so grant its accessibility permission and
review its login-item setting. Quit Hidden Bar before using Tuckaway to avoid
competing menu-bar restrictions.

## Use

1. Hold **⌘** and drag icons to arrange them relative to Tuckaway’s arrow.
   Icons on the hidden side collapse; icons on the visible side remain.
2. Click the arrow to collapse or expand. Right-click also toggles;
   Control-right-click opens the menu.
3. Open **Preferences** to configure auto-collapse, startup, icon style,
   hover, separate-bar display, and display-specific behavior.
4. Option-click the arrow, or choose **Hide/Show Separators**, to toggle the
   always-hidden presentation.

On macOS 27, grant Tuckaway access under **System Settings → Privacy & Security
→ Device Control and Data Access**. Other macOS versions call this
**Accessibility**.

## Build from source

Install current Xcode, then run:

```sh
xcodebuild -project "Tuckaway.xcodeproj" -scheme "Tuckaway" \
  -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO build
```

Run the complete test suite with:

```sh
xcodebuild -project "Tuckaway.xcodeproj" -scheme "Tuckaway" \
  -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO test
```

Local unsigned or ad-hoc-signed builds can require a fresh permission grant
when their signature changes.

## Documentation

- [Manual](docs/MANUAL.md): settings, permissions, behavior, and troubleshooting
- [Architecture](docs/ARCHITECTURE.md): hiding engines, topology, and known limits
- [Maintainer runbook](docs/RUNBOOK.md): build, verification, and release process
- [Upstream issue status](docs/UPSTREAM_ISSUES.md): integrated fixes and external blockers

## Privacy

Tuckaway has no analytics, accounts, network service, or third-party tracking.
Permissions are used locally to read menu-bar layout, capture hidden items when
requested, and forward clicks. See [Privacy Policy](PRIVACY_POLICY.md).

## Acknowledgments

Tuckaway incorporates work from Hidden Bar’s contributors and from the upstream
pull requests listed in the project history. The original copyright and MIT
license notices are preserved in [LICENSE](LICENSE).

## License

MIT © Dwarves Foundation, with Tuckaway modifications maintained by
Bruno-Alumn. See [LICENSE](LICENSE).
