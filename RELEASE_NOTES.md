# v0.0.1 — First preview

Moving from Windows should not mean relearning how to find a runaway process or close a frozen app. Task Manager for Omarchy brings familiar controls into a native floating panel, with mouse and keyboard support and fonts and colors drawn from Omarchy.

This first preview includes process and application management, CPU/memory/disk/network graphs, driver-dependent GPU readings, startup controls, user and system service controls, session information, and local usage history.

The hardening pass adds safer process identity checks, protected desktop services, atomic state writes, clearer errors, and regression coverage. CI builds the Rust worker and Qt interface, tests disposable process and real systemd service actions, and builds, installs, reinstalls and removes the Arch package.

## Install on Omarchy / Arch x86_64

Download the attached package and SHA256SUMS into the same directory, then run:

```bash
sha256sum --ignore-missing --check SHA256SUMS
sudo pacman -U ./omarchy-task-manager-0.0.1-1-x86_64.pkg.tar.zst
omarchy-task-manager
```

Proceed with installation only if the package checksum is reported as OK. The source archive and a checksummed local PKGBUILD are also attached for building with `makepkg -si` as your normal user. Optional `nvidia-utils` supplies NVIDIA counters; optional `gdb` enables live process core dumps.

## Preview boundaries

Live Omarchy placement, scaling, session/polkit behavior, and real GPU accuracy still need hardware acceptance. GPU availability depends on the driver; missing readings appear as dashes. Per-application network traffic and Windows-specific power or boot-impact scores are not implemented. See FEATURES.md and the README for the full boundaries.

We will iterate through **v0.0.n** while testing and refining the app. **v0.1.0** is reserved for when we are happy with it.
