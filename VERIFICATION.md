# v0.1.0 release acceptance

On 24 September 2026, Tom confirmed that the outstanding XPS checks discussed for v0.0.5 were complete and looked good, and approved the first non-preview v0.1.0 release. These checks cover background monitoring startup after logout/reboot and GPU readings on his hardware, in addition to the previously accepted Summary and Super + W/reopen behaviour.

This is maintainer-reported live acceptance of v0.0.5 (`a83b2db848d9784ecad8d772f245eb2307fc2c37`), not a new desktop test performed by the release-preparation environment. Exact installed OS/driver versions, per-step logs and fresh screenshots were not supplied. It does not establish compatibility with all Intel/AMD/NVIDIA devices, ARM, or completion of every historical exploratory check below.

v0.1.0 preserves that application behaviour, changes version labels and release documentation, and publishes without the prerelease flag. Its release workflow requires fresh Ubuntu/Arch CI, package lifecycle checks and checksummed assets from the release commit. BUILD-INFO.txt identifies that commit and workflow run. The historical records below retain their original scope; later CI and the maintainer's acceptance above supersede their pending status only for the checks actually covered.

---

# Historical verification — expanded pre-release build

> Historical record: this work used the planned v0.1.0 label. The first published preview is v0.0.1; we will iterate through v0.0.n before v0.1.0. Existing evidence and hashes describe their original inputs, not the release commit. Release CI supplies fresh build results and asset checksums.

Date: 20 September 2026. Environment: Ubuntu 24.04 x86_64, GCC 13, Qt 6.4.2, Rust 1.98.1. No live Omarchy session or accessible GPU. Unix sockets are forbidden by this execution environment. Source hashes are in EVIDENCE.sha256; these results cover the expanded archive, not a remote commit or published release.

## Passed here

- Rust formatter and `cargo clippy --locked --all-targets -- -D warnings`.
- 17 Rust unit tests: procfs parsing, identity/ownership/protection, real disposable termination, CPU accounting/discontinuities, app ancestry boundaries, DRM units/capacity parsing, startup-section preservation and path/unit validation.
- Qt bridge suite: live worker, rows, filtering, sorting, stable-key selection, preferences validation, protected targets and pause behavior.
- Qt UI suite: actual QML loading/rendering; Ctrl+2/3 and search; force-quit cancellation/confirmation against a disposable sleep; every page including both service scopes; new-task dialog focus; footer geometry within the window.
- A real Qt 6.4 layout crash during rapid page changes was reproduced. Dynamic table cells now use explicit row geometry instead of layout-managed repeater children; the complete navigation regression passes.
- Real worker protocol tests: first/second metrics, stale identities, self-protection, theme-directory replacement; process inspection; SIGSTOP/SIGCONT; setting a disposable child's nice value and verifying with getpriority; CPU affinity and verifying with sched_getaffinity; invalid priority/affinity; protected/injected service names; foreign-session denial; invalid restart; atomic per-user autostart disable/enable with the system source unchanged; history reset/persistence; management-page snapshots; termination and exited-PID errors.
- `desktop-file-validate`.
- CMake release build and staged installation under `target/full-stage/usr`. The installed GUI located the worker in `usr/lib/omarchy-task-manager` and passed the offscreen smoke test.
- Actual offscreen screenshots of the running process and performance pages. These show Ubuntu/fontconfig fallback styling and real container counters, not a simulated XPS workload or a Hyprland desktop.

The Qt suites passed 2/2; the protocol runner printed PASS for both its core and expanded management checks. Compositor IPC tests explicitly printed SKIP because Unix sockets are blocked.

## Still requires the target

- Real Hyprland window discovery/focus/close, floating placement, repeat-instance activation, dragging, blur dismissal, multiple monitors and display scaling.
- Active Omarchy theme/font changes (especially Familiar), full shell-token appearance and accessibility at enlarged sizes. Not every Quattro style token is supported.
- App restart with real GUI desktop launchers, browser/portal/Flatpak/Wine grouping.
- GPU-equipped Intel/AMD/NVIDIA machines: driver counter availability, observed-client versus whole-device accuracy, shared client attribution, driver resets.
- Real service inventory/lifecycle/enable/disable and journal permissions; lock and sign-out. The container lacks a usable systemd/login session. No real session was terminated.
- Core dump capture with gdb/ptrace access. The missing-tool/permission path is implemented; successful memory capture was not exercised here.
- Run-new-task launching and file-manager opening through the actual desktop session. The run dialog and direct-argument launch implementation were checked, but no GUI child was launched in headless tests.
- Arch `makepkg`, `namcap`, install/upgrade/removal; remote GitHub Actions. The archive includes a checksummed PKGBUILD and CI definitions, but neither remote CI nor an Arch package build is claimed.
- Sustained XPS CPU/RSS budgets, suspend/resume and hotplug under real workloads. No performance-budget certification is claimed.

Use README.md's XPS acceptance sequence before tagging v0.1.0. The source is now prepared for tcballard/omarchy-task-manager. This document records local evidence before the first push; check GitHub Actions for subsequent remote results. No tag, release, marketplace issue or package submission has been created.
