# v0.1.0 — Find the frozen app. Get back to work.

Task Manager for Omarchy's first non-preview release gives you a familiar, mouse-friendly way to see what's running, find a misbehaving application and close it.

v0.1.0 carries forward the behaviour tested in v0.0.5. This release updates version labels and documentation; it adds no new application features.

- **Start with Summary.** See running applications and compact CPU and memory graphs, then find an app by name.
- **Close an app with care.** Request a normal close first. If it won't cooperate, Force quit names the target and asks for confirmation.
- **See what happened before you opened it.** Background monitoring retains the last minute of CPU, memory, disk and network readings, including while the window is closed with Super + W.
- **Go deeper when needed.** Performance, processes, services and startup applications remain available. GPU readings depend on the driver and hardware.
- **Fits your desktop.** Omarchy colours and fonts, a movable and resizable window, remembered preferences and keyboard controls.

## Install or upgrade

Download the [x86_64 package](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.1.0/omarchy-task-manager-0.1.0-1-x86_64.pkg.tar.zst) and [SHA256SUMS](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.1.0/SHA256SUMS) into the same directory, then run:

```bash
sha256sum --ignore-missing --check SHA256SUMS &&
sudo pacman -U ./omarchy-task-manager-0.1.0-1-x86_64.pkg.tar.zst
```

Open **Task Manager** from the launcher. [Super + Alt + Delete](https://github.com/tcballard/omarchy-task-manager/blob/v0.1.0/docs/GUIDE.md#keyboard-shortcut) is an optional, one-time shortcut setup.

The existing [Omarchy packaging PR](https://github.com/omacom/omarchy-pkgs/pull/594) handles the channel update separately. `sudo pacman -Syu omarchy-task-manager` installs whichever version your channel currently publishes; this GitHub release does not itself promote the package to Edge, RC or Stable.

## Tested on the XPS

Tom accepted v0.0.5 on his XPS, including Summary and background history, and confirmed the remaining logout/reboot startup and GPU checks on 24 September 2026. v0.1.0 preserves that behaviour. Fresh release CI builds and tests on Ubuntu and Arch, including real user-service controls and package installation, upgrade, reinstall and removal. `BUILD-INFO.txt` identifies the release commit; `SHA256SUMS` covers its assets.

That acceptance covers this XPS, not every GPU or driver. ARM is not supported by the published package. Per-app network traffic is unavailable; detailed process, service and GPU polling runs while the window is open. The existing screenshot predates Summary and background monitoring.

## Background monitoring and removal

The first normal installed launch enables a user service. Background monitoring can be disabled in the menu; Pause live view only freezes the displayed readings. History stays local, and the collector has no network listener.

Before removal or downgrade, turn Background monitoring off or run:

```bash
systemctl --user disable --now omarchy-task-manager-monitor.service
```

Preferences and application history survive removal. The last-minute graph cache is temporary. A verified v0.0.5 package remains available for rollback; v0.1.0 introduces no state-format changes.

[Changes since v0.0.5](https://github.com/tcballard/omarchy-task-manager/compare/v0.0.5...v0.1.0)
