# v0.0.3 — Ready for repository packaging

![Task Manager for Omarchy on a Dell XPS, showing applications, icons and resource usage](https://raw.githubusercontent.com/tcballard/omarchy-task-manager/cfdd96635c3a0ef697be82d27cea411d27f3fbf2/docs/screenshots/task-manager-familiar.png)

*On-device capture with the Familiar theme from before the v0.0.2 version bump. This release changes packaging; the interface is unchanged apart from its version label.*

**Installing Task Manager should be the easy bit. v0.0.3 prepares it for Omarchy’s package repository.**

The goal is simple: install it once, then get updates with the rest of your system. This release supplies the recipe and update metadata for that upstream contribution. **It is not yet available from the official Omarchy repository.**

## What changed

- **One package recipe.** Local builds and the Omarchy contribution use the same versioned source archive and SHA-256 checksum.
- **Preview update tracking.** The proposed repository entry follows published GitHub previews and targets the edge channel while we iterate through v0.0.n.
- **Better installation checks.** CI now checks package contents and dependencies, fresh installation, upgrading from v0.0.2, reinstalling and removing. It checks that existing preferences and history survive.
- **An icon dependency fixed.** The new package checks caught a missing declaration for `hicolor-icon-theme`. It is now included.

## Install or upgrade now

For **Omarchy / Arch x86_64**, download the [package](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.0.3/omarchy-task-manager-0.0.3-1-x86_64.pkg.tar.zst) and [SHA256SUMS](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.0.3/SHA256SUMS) into the same directory, then run:

```bash
sha256sum --ignore-missing --check SHA256SUMS &&
sudo pacman -U ./omarchy-task-manager-0.0.3-1-x86_64.pkg.tar.zst
omarchy-task-manager
```

Check that the package checksum reports `OK`. These commands work for a fresh install or an upgrade. Pacman installs the required dependencies. You can also open **Task Manager** from the app launcher.

**Super + Alt + Delete** still needs the [one-time setup](https://github.com/tcballard/omarchy-task-manager/blob/v0.0.3/README.md#keyboard-shortcut). Installation does not edit your personal bindings.

## Repository submission

The attached `omarchy-task-manager-0.0.3-omarchy-pkgs.tar.gz` contains the two-file contribution for `omacom/omarchy-pkgs`. Upstream review, acceptance and publication come next. Normal repository installation and updates become available only when the package is published on your configured channel.

Building locally? Download the source archive and PKGBUILD into the same directory, verify their checksums and run `makepkg -si` as your normal user. The debug package is optional.

## Still a preview

Publication is gated on Ubuntu and Arch CI for the release commit, including the package lifecycle checks above, Rust/Qt tests, worker protocol tests and real systemd service controls. `BUILD-INFO.txt` identifies the exact source and run; the attached namcap report and package file list record packaging evidence. Static lint warnings for runtime plugins and subprocess dependencies are retained for review.

The earlier XPS testing is useful context, not a new live acceptance result for v0.0.3. The official Omarchy builder and fresh Wayland/launcher checks remain part of upstream submission validation. ARM and full GPU accuracy are not claimed. The simpler End task flow and in-app shortcut setup remain planned.

We’re continuing through **v0.0.n** until the everyday experience is ready for **v0.1.0**. If installation or upgrading gets in your way, [tell us what happened](https://github.com/tcballard/omarchy-task-manager/issues).

<details>
<summary>Rollback and removal</summary>

To roll back, verify and install the package from [v0.0.2](https://github.com/tcballard/omarchy-task-manager/releases/tag/v0.0.2) with `sudo pacman -U`. This release makes no settings or history-format changes.

Remove with `sudo pacman -R omarchy-task-manager`. Preferences and history remain; remove any manually added shortcut separately.

</details>

[All changes since v0.0.2](https://github.com/tcballard/omarchy-task-manager/compare/v0.0.2...v0.0.3)
