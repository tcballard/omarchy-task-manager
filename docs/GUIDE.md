# Task Manager guide

[Back to the overview](../README.md). Build commands below run from the repository root.

## Build and run on Omarchy

For a fresh install without compiling, download the package and checksums from the
[GitHub releases](https://github.com/tcballard/omarchy-task-manager/releases)
and follow that release’s install commands. The same package upgrades an existing installation.

The app was [published to Omarchy's edge repository](https://github.com/omacom/omarchy-pkgs/pull/579#issuecomment-5766245954) as **0.0.3-3** on 21 September 2026. If you already use edge, install with `sudo pacman -Syu omarchy-task-manager`. The repository package includes the pause/resume test and worker-shutdown fixes backported from app PRs #11 and #12. The original GitHub v0.0.3 package predates those fixes. v0.0.4 includes both fixes directly; its proposed promotion beyond Edge remains a separate upstream decision. A GitHub preview package does not change the package available on an Omarchy channel. See the [packaging handoff](OMARCHY_PACKAGING.md).

Clone the repository and build as your normal user:

```bash
sudo pacman -S --needed git base-devel cmake ninja rust cargo qt6-base qt6-declarative qt6-wayland qt6-svg python desktop-file-utils
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

### Keyboard shortcut

Our default shortcut is **Super + Alt + Delete**: open Task Manager, or focus it if already running. It never ends an application directly. Super is the Windows/logo key on most keyboards.

For current Omarchy Quattro, open **Super + K** and check that this combination is not already assigned by your own configuration. Add the following line once to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + DELETE", "Task Manager", "omarchy-task-manager")
```

Reload Hyprland with `hyprctl reload`, then try the shortcut. The package ships this configuration in `/usr/share/omarchy-task-manager/bindings.lua.example`; source builds include `packaging/bindings.lua.example`. Package installation alone does not activate it or edit your personal bindings. Remove the line and reload to disable it, including when uninstalling the app.

Super + Alt + Delete is unassigned in the upstream Omarchy dev bindings checked at `b9ddccfc377abe0b8fc3ff1ee5b31a86bf202d4a`. Local customisations may differ. Ctrl + Alt + Delete is already assigned to **Close all windows**, so it is not our shortcut. This recipe targets Quattro's Lua configuration; older Hyprland configurations use different syntax.

## Floating panel

The app requests floating placement for its own Hyprland window, centers it on the focused monitor, and uses a frameless draggable header. Reopening focuses the existing instance. Use the top-left menu button to collapse the sidebar to an icon rail, and drag the bottom-right grip to resize the panel. Navigation and column widths are saved locally. The header and action controls fit the window; long lists and wide optional columns scroll within their own views. **Stay open** keeps it visible while you switch applications; turn this off for dismissal when focus leaves the panel. Escape, Super + W or the close button exits and releases the detailed worker. Background monitoring continues independently when enabled. This is a standalone window, not a bar-anchored Quickshell plugin or fullscreen overlay.

Colors are read from `$XDG_STATE_HOME/omarchy/current/theme/colors.toml` (default `~/.local/state/omarchy/current/theme/colors.toml`), with the legacy `~/.config/omarchy/current/theme` used only when the state theme directory is absent; popup colors, font sizes, and supported control fills/widths come from `shell.toml`. Invalid or incomplete base palettes fall back together. Font family is `monospace`, following Omarchy's fontconfig alias. Theme replacement is detected by rereading on active samples. Theme gradients, per-edge borders, spacing overrides, opacity and Hyprland corner-radius overrides are not fully mirrored; the panel currently uses a solid accent border and square corners. Font-family changes may require reopening because Qt/fontconfig caches aliases.

## Familiar controls

Summary opens by default on a fresh install. It puts up to eight running applications ordered by CPU use above compact CPU and memory history. Select an application for its normal close controls, or use **Find an app** to search the full Applications list. Your last page remains saved across launches. CPU use alone does not mean an application is frozen.

**Background monitoring** is enabled on the first normal launch of the updated installed package. It collects basic CPU, memory, disk and network metrics once per second and retains up to 60 seconds while the window is closed. Super + W closes the window; reopening restores recent history. The menu shows the setting and service setup errors. Turn it off to disable and stop the collector, including startup on future logins. The choice is remembered. Collection starts at first launch, then at later user-manager starts; it cannot recover time before it started. Failed setup falls back to ordinary live monitoring.

**Pause live view** (and an action confirmation) freezes the displayed readings; resuming starts a fresh live baseline. The collector continues independently. **Stay open** controls dismissal on focus loss only. GPU and per-app history are collected only while the app runs; the collector does not scan processes or query services. UI refresh speed and the fixed one-second background cadence are independent.

- Ctrl+0: Summary. Ctrl+1 through Ctrl+7: the other seven pages. Ctrl+F: search. Ctrl+N: run a new task. F5: refresh. Escape: dismiss a dialog or close the panel.
- Click a column heading to sort; drag its right divider to resize (or focus the heading and press Shift+Left/Right). Double-click a divider or choose **Columns → Reset column widths** to restore automatic sizing. Use **Columns** for disk I/O, GPU, owner and thread counts. Up/Down selects rows; right-click or **More** exposes process actions.
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

The App history page records your processes grouped by executable only while the detailed UI worker samples. It is separate from the basic background graphs. Data is saved every 30 seconds and at normal exit. It cannot account for processes that start and exit entirely between samples. Per-app network traffic, Windows power-impact scores, boot-impact timings, UWP counters, and Windows wait-chain analysis have no direct implementation here.

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
8. Build with `makepkg`, run `namcap`, install, upgrade and remove on the target. Preferences/history should remain. Remote CI, real systemd/session actions, Hyprland placement and hardware acceptance must be recorded before shipping v0.1.0. The v0.0.n previews are for testing while this acceptance remains incomplete.

## Removal

If you enabled background monitoring, turn it off in the app menu or run this before removal or downgrade:

```bash
systemctl --user disable --now omarchy-task-manager-monitor.service
sudo pacman -R omarchy-task-manager
```

Preferences live at `$XDG_CONFIG_HOME/tcballard/omarchy-task-manager.conf`; history and dumps live at `$XDG_STATE_HOME/omarchy-task-manager` (defaults: `~/.config` and `~/.local/state`). Package removal preserves both. XDG startup overrides remain in your `autostart` directory; re-enable entries in the app before uninstalling if desired. btop remains installed.

See [FEATURES.md](../FEATURES.md), [ARCHITECTURE.md](../ARCHITECTURE.md), [CREDITS.md](../CREDITS.md), and [VERIFICATION.md](../VERIFICATION.md). [SCOPE.md](../SCOPE.md) preserves the original, narrower planning document; the current feature matrix supersedes it.

Our design starts with someone who wants to find and close a frozen app without learning Linux internals. See [product direction and acceptance scenarios](../PRODUCT.md) for the experience we are working towards, and [contributor instructions](../AGENTS.md) for how we keep changes aligned.

## Background collector: testing and removal

After installing this development build, launch Task Manager once and check **Background monitoring** in its menu. Leave it for ten seconds, close with Super + W, wait ten more seconds and reopen. CPU/memory graphs should already contain recent history. Switch the setting off, close/reopen and check that it stays off and graphs start fresh. Check pause/resume separately: the live view freezes while a new window can still load the independent collector's history.

For a source build, install the executable and generated user unit together using the same configured CMake install prefix, then run `systemctl --user daemon-reload`. Running a development binary alone does not install the collector; the menu reports that limitation. Check service state with `systemctl --user status omarchy-task-manager-monitor.service`.

Before uninstalling or rolling back, turn Background monitoring off or run:

```bash
systemctl --user disable --now omarchy-task-manager-monitor.service
```

Removing the binary also makes a running collector exit on its next iteration. User preferences and existing App history are preserved. Recent background data lives only under `$XDG_RUNTIME_DIR/omarchy-task-manager-monitor` and is removed on clean collector shutdown or runtime-directory cleanup.
