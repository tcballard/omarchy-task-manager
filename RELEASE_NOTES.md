# v0.1.1 — Less overhead when your computer is slow

Task Manager should help when the desktop is slow, not add to the load. This maintenance release reduces the cost of sampling and sending data while preserving the familiar Summary and safe close/force-quit flow.

- **Sample GPU clients more cheaply.** Only DRM and accelerator descriptors are read for GPU attribution. On NVIDIA desktops, one bounded, supervised `nvidia-smi` stream replaces a new process every sample. On the contributor's RTX 3080 desktop, measured worker plus child CPU fell from about 12% to 3% of one core with the window open at the default one-second interval. This is a measurement on that machine, not an all-hardware guarantee.
- **Send smaller snapshots.** The full process list goes to Applications and Processes; other pages retain the process count but avoid parsing hundreds of unused rows each second. Switching pages fetches fresh rows immediately.
- **Make local tests reliable.** The Qt test suites use a private runtime directory, so a developer's running background monitor cannot change their assertions.

## Install or upgrade

Download the [x86_64 package](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.1.1/omarchy-task-manager-0.1.1-1-x86_64.pkg.tar.zst) and [SHA256SUMS](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.1.1/SHA256SUMS) into the same directory, then run:

```bash
sha256sum --ignore-missing --check SHA256SUMS &&
sudo pacman -U ./omarchy-task-manager-0.1.1-1-x86_64.pkg.tar.zst
```

Open **Task Manager** from the launcher. [Super + Alt + Delete](https://github.com/tcballard/omarchy-task-manager/blob/v0.1.1/docs/GUIDE.md#keyboard-shortcut) is an optional one-time shortcut setup.

The [Omarchy package PR](https://github.com/omacom/omarchy-pkgs/pull/594) handles channel updates separately. `sudo pacman -Syu omarchy-task-manager` installs whichever version your channel publishes; the GitHub release does not itself promote a package to Edge, RC or Stable.

## Verification and limits

The v0.1.0 release was accepted on Tom's XPS for Summary, background monitoring, logout/reboot startup and GPU readings. The v0.1.1 changes have contributor testing on an NVIDIA desktop and portable tests; **the new GPU sampling path and page transitions still need a v0.1.1 XPS check**. AMD/Intel hardware and ARM are not covered by the contributor's measurements. NVIDIA streaming trades roughly 25 MiB of resident memory for lower CPU use while the window is open. Readings can be up to one second old at the fastest refresh setting.

The release workflow builds on Ubuntu and Arch, checks the package lifecycle, and publishes only after those jobs pass on the release commit. `BUILD-INFO.txt` identifies the commit and workflow run; `SHA256SUMS` covers the assets. The per-user background service and local state format are unchanged.

Before removal or downgrade, turn Background monitoring off or run:

```bash
systemctl --user disable --now omarchy-task-manager-monitor.service
```

Preferences and application history survive removal. A verified v0.1.0 package remains available for rollback.

[Changes since v0.1.0](https://github.com/tcballard/omarchy-task-manager/compare/v0.1.0...v0.1.1)
