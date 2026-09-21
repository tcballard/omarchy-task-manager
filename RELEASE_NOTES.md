# v0.0.2 — Desktop polish

Task Manager should help you find a misbehaving app and get back to work. This preview improves how the panel fits your desktop and how easily you can recognise the apps inside it, following maintainer on-device testing.

## Changes since v0.0.1

- Live themes now follow Omarchy's current state-directory layout, with support for the older config-directory layout.
- The panel fits smaller logical screens, with updated Hyprland floating-window dispatch and a legacy fallback.
- Application icons now use the desktop icon theme, including SVG support and an Omarchy icon for Omarchy-namespaced windows.
- A collapsible sidebar and resizable table columns make better use of the available space; those preferences are saved.
- Super + Alt + Delete is the supplied shortcut to open or focus Task Manager. It still requires the one-time activation described in the README; installation does not rewrite personal bindings.
- Product and contributor guidance now put finding and closing a frozen app first. The simpler End task journey and in-app shortcut setup remain planned work.

## Install or upgrade — Omarchy / Arch x86_64

Download the attached package and SHA256SUMS into the same directory, then run:

```bash
sha256sum --ignore-missing --check SHA256SUMS &&
sudo pacman -U ./omarchy-task-manager-0.0.2-1-x86_64.pkg.tar.zst
omarchy-task-manager
```

Confirm the package checksum reports OK. The source archive and local PKGBUILD are attached for builds with `makepkg -si` as your normal user. The debug package is optional. Pacman installs the new `qt6-svg` dependency for desktop icons.

To return to v0.0.1, download its package and checksums from that release, verify them and install the older package with `sudo pacman -U`. This release adds UI preferences and does not introduce a history-format migration; older builds ignore the added preferences. Package removal with `sudo pacman -R omarchy-task-manager` preserves preferences/history. Remove any manually added shortcut separately.

## Verification and preview boundaries

Tom reported on-device testing and readiness for v0.0.2 on 21 September 2026. The repository contains an XPS screenshot dated the same day. The exact tested commit, Omarchy/Hyprland versions and individual acceptance results were not supplied with that report, so this is not a claim that the full desktop/GPU checklist passed.

Publication is gated on fresh Ubuntu and Arch CI for the release commit, including Rust, Qt, worker protocol, real systemd service controls and package installation/reinstallation/removal. BUILD-INFO.txt identifies the asset source commit and workflow run; SHA256SUMS covers the attached assets. Headless CI does not establish GPU accuracy or all live desktop/session behaviours.

We will continue through **v0.0.n** while refining the app, reserving **v0.1.0** for readiness. See the README and FEATURES.md for remaining limitations.

[Changes since v0.0.1](https://github.com/tcballard/omarchy-task-manager/compare/v0.0.1...v0.0.2)
