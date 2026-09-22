# v0.0.4 — Beyond Edge

![Task Manager running on my XPS with the Familiar theme](https://raw.githubusercontent.com/tcballard/omarchy-task-manager/cfdd96635c3a0ef697be82d27cea411d27f3fbf2/docs/screenshots/task-manager-familiar.png)

*Captured on my XPS on 21 September. The interface is unchanged apart from its version label.*

**Task Manager is ready for the next step beyond Edge.**

v0.0.4 brings the fixes already carried by the Edge package into the release itself and prepares the package for Omarchy's RC and Stable channels. Upstream promotion still needs to merge and publish before those channels can install it through pacman.

- **Safer shutdown.** Timers and worker callbacks stop before the window's bridge is destroyed, fixing the shutdown crash found during packaging.
- **Reliable pause/resume checks.** Tests capture the resumed sample when it arrives, removing the timing failure that blocked the first official build.
- **A simpler package.** Both fixes are included in the source, so the two downstream patches can go. The package keeps the same name, preferences and history.

## Install or upgrade

On Omarchy's **Edge channel**:

```bash
sudo pacman -Syu omarchy-task-manager
```

This installs the version currently published on your channel. The same command will work on RC and Stable once the promotion is published.

For v0.0.4 now on Omarchy / Arch x86_64, download the [package](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.0.4/omarchy-task-manager-0.0.4-1-x86_64.pkg.tar.zst) and [SHA256SUMS](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.0.4/SHA256SUMS) into the same directory:

```bash
sha256sum --ignore-missing --check SHA256SUMS &&
sudo pacman -U ./omarchy-task-manager-0.0.4-1-x86_64.pkg.tar.zst
```

Check that the package reports `OK`, then open **Task Manager** from the launcher. [Super + Alt + Delete setup](https://github.com/tcballard/omarchy-task-manager/blob/v0.0.4/docs/GUIDE.md#keyboard-shortcut) remains optional.

## Still improving

This remains a **v0.0.x preview**. Wider package availability does not make it v0.1.0. GPU readings depend on your driver, and the simpler End task flow remains planned.

Publication is gated on Ubuntu and Arch CI, including Rust/Qt tests, repeated shutdown and pause/resume checks, sanitizers, package lint and installation/upgrade/removal checks. The attached `BUILD-INFO.txt` identifies the exact source and run; `SHA256SUMS` covers the assets. Earlier XPS testing is historical; this release does not claim a new live desktop or ARM test.

Remove with `sudo pacman -R omarchy-task-manager`; preferences and history remain. For rollback, use a verified cached `0.0.3-3` Edge package with `sudo pacman -U`. The original GitHub v0.0.3 package predates the shutdown fix. There is no settings or history-format migration.

[All changes since v0.0.3](https://github.com/tcballard/omarchy-task-manager/compare/v0.0.3...v0.0.4)
