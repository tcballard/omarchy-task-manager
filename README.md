# Task Manager for Omarchy

<a href="#build-and-run-on-omarchy"><img src="https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-app.svg" alt="Built for Omarchy — App" height="20"></a>

**See what’s running. Take control.**

We built Task Manager for Omarchy because moving from Windows shouldn't mean relearning how to find a runaway process or close a frozen app. btop is a capable monitor; we wanted a graphical place to see what's running, understand resource use, and manage processes, startup apps and services. It brings familiar controls into a native, mouse-friendly floating panel, with keyboard support and fonts and colors drawn from Omarchy.

**[Build and run on Omarchy →](#build-and-run-on-omarchy)**

**v0.1.0 preview.** Live Omarchy and GPU acceptance remain pending. Read the [verification record](VERIFICATION.md) and [feature coverage and Linux differences](FEATURES.md) before trying it.

## Build and run on Omarchy

Clone the repository and build as your normal user:

```bash
sudo pacman -S --needed git base-devel cmake ninja rust cargo qt6-base qt6-declarative qt6-wayland python desktop-file-utils
git clone https://github.com/tcballard/omarchy-task-manager.git
cd omarchy-task-manager
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build -j 4
./build/omarchy-task-manager
```

The build places the GUI and its Rust worker beside one another. Keep them together. Qt 6.4+ is supported; this workspace uses Qt 6.4.2. Cargo.lock pins dependencies. Rustup users select the checked-in 1.98.1 toolchain; system Rust/Cargo can also build it.

To build an Arch package from the checkout, generate its checksummed source tarball and recipe:

```bash
./scripts/package-source.sh
cd dist
makepkg -si
```

Run `makepkg` as your normal user. After installation, find **Task Manager** in the app launcher or run `omarchy-task-manager`. `scripts/package-source.sh` regenerates the source tarball and recipe after changes. No shortcut, existing config, or btop package is overwritten. Optional `gdb` enables live core dumps; optional `nvidia-utils` supplies NVIDIA device counters.

An optional Ctrl+Shift+Escape example for current Quattro is in `packaging/bindings.lua.example`. Check for conflicts before adding it to your own bindings. Older Hyprland configurations use their own syntax.

## Floating panel

The app requests floating placement for its own Hyprland window, centers it on the focused monitor, and uses a frameless draggable header. Reopening focuses the existing instance. **Stay open** keeps it visible while you switch applications; turn this off for dismissal when focus leaves the panel. Escape or the close button exits and releases the worker. This is a standalone window, not a bar-anchored Quickshell plugin or fullscreen overlay.

Colors are read from `~/.config/omarchy/current/theme/colors.toml`; popup colors, font sizes, and supported control fills/widths come from `shell.toml`. Invalid or incomplete base palettes fall back together. Font family is `monospace`, following Omarchy's fontconfig alias. Theme replacement is detected by rereading on active samples. Theme gradients, per-edge borders, spacing overrides, opacity and Hyprland corner-radius overrides are not fully mirrored; the panel currently uses a solid accent border and square corners. Font-family changes may require reopening because Qt/fontconfig caches aliases.

## Familiar controls

- Ctrl+1 through Ctrl+7: the seven pages. Ctrl+F: search. Ctrl+N: run a new task. F5: refresh. Escape: dismiss a dialog or close the panel.
- Click a column heading to sort. Use **Columns** for disk I/O, GPU, owner and thread counts. Up/Down selects rows; right-click or **More** exposes process actions.
- **Close window** requests a normal close for an application's first window, permitting a save prompt. **Terminate** sends SIGTERM. **Force quit** sends SIGKILL. **End process tree** confirms the fixed descendants found in the current snapshot.
- Application restart terminates the selected group and invokes its known desktop launcher. If it does not exit within three seconds, the app is not relaunched automatically.
- Priority and affinity apply to existing threads. **Lower priority** uses Linux nice; it does not claim to cap power or reproduce Windows EcoQoS. Raising priority or restoring a lower nice value may require additional permission.
- **Details** shows executable, command, working directory, threads/wait channels, open files, cgroup and memory mappings. **Create core dump** uses optional gdb, obeys ptrace permissions, and writes into a private local folder after confirmation.
- Startup toggles create atomic per-user XDG desktop-entry overrides, leaving system entries intact. Hyprland Lua/conf startup files are exposed for inspection/editing, not rewritten as if they were simple checkboxes.
- Services can be started, stopped, restarted, enabled/disabled at login/boot, and inspected through the journal. Both user and system scopes are available; systemd enforces permissions, and the app does not run itself as root or install a privilege helper.
- Users shows aggregate resource consumption and available login sessions. Lock/sign-out controls are limited to your own sessions. Sign-out ends that session's work.
- Export saves the current JSON snapshot into Documents. It contains process commands and paths. History reset deletes only this app's recorded usage history.

CPU percentages are normalized to total machine capacity. Application and user memory sums RSS, which can double-count shared pages. A Linux sleeping/waiting state is not presented as proof that an app is unresponsive. Unknown readings are shown as dashes. Read/write and network graphs use adaptive scales; CPU/memory graphs use 0–100%.

## Data and limitations

History records your processes grouped by executable while this monitor is actively sampling; it is not an always-on background service. Data is saved every 30 seconds and at normal exit. It cannot account for processes that start and exit entirely between samples. Per-app network traffic, Windows power-impact scores, boot-impact timings, UWP counters, and Windows wait-chain analysis have no direct implementation here.

DRM GPU readings depend on exported driver counters and readable client file descriptors. Shared DRM clients are counted once; the process receiving that attribution may not be the only owner. Intel-style observed-client utilization is not guaranteed to be whole-device utilization. AMD device counters and optional NVIDIA counters are used where available. No GPU-equipped machine was available for acceptance in this workspace.

Applications are attributed through Hyprland windows and ancestry with shell/user boundaries. Flatpak, Wine, portals and shared helpers may require inspection through Processes; complete cgroup attribution is not claimed.

## Local verification

```bash
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
ctest --test-dir build --output-on-failure
python3 tests/protocol.py build/omarchy-task-manager-core
desktop-file-validate packaging/io.github.tcballard.TaskManager.desktop
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./build/omarchy-task-manager --smoke
```

Actions in automated tests target disposable children and temporary startup files. Tests skip compositor IPC explicitly if Unix sockets are forbidden. Offscreen Qt testing does not establish real Wayland placement or GPU compatibility. [GitHub Actions](https://github.com/tcballard/omarchy-task-manager/actions) builds/tests on Ubuntu and builds an Arch package artifact. Check the run for your commit; headless CI does not establish live desktop acceptance.

## Live XPS acceptance

1. Run `scripts/xps-check.sh` and record versions. Build/install as a normal user. Open through the launcher, reopen to focus, test drag/float placement on each monitor, Escape and dismissal on blur.
2. Switch dark/light/Familiar themes while open. Check text, controls, selection, scaling and scrolling.
3. Inspect a browser, an editor with unsaved text, and terminal-launched jobs. Close should preserve save prompts. Test termination/restart only on disposable work.
4. Launch `sleep 300`; verify cancellation, suspend/resume, nice, affinity and termination against that PID. Do not test these on the desktop shell.
5. Compare CPU/RSS/disk/network/GPU over equivalent intervals with btop and driver tools. Test suspend/resume and device/network changes.
6. Toggle a disposable XDG autostart entry and restore it. Create a disposable user service and test its lifecycle/logs. Confirm denied system-service actions show useful errors.
7. Test session lock; test sign-out only after saving work. Test optional core dumps only on a disposable process. Verify history survives reopening and reset works.
8. Build with `makepkg`, run `namcap`, install, upgrade and remove on the target. Preferences/history should remain. Remote CI, real systemd/session actions, Hyprland placement and hardware acceptance must be recorded before tagging.

## Removal

```bash
sudo pacman -R omarchy-task-manager
```

Preferences live at `$XDG_CONFIG_HOME/tcballard/omarchy-task-manager.conf`; history and dumps live at `$XDG_STATE_HOME/omarchy-task-manager` (defaults: `~/.config` and `~/.local/state`). Package removal preserves both. XDG startup overrides remain in your `autostart` directory; re-enable entries in the app before uninstalling if desired. btop remains installed.

See [FEATURES.md](FEATURES.md), [ARCHITECTURE.md](ARCHITECTURE.md), [CREDITS.md](CREDITS.md), and [VERIFICATION.md](VERIFICATION.md). [SCOPE.md](SCOPE.md) preserves the original, narrower planning document; the current feature matrix supersedes it.
