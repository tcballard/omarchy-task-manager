# Omarchy Task Manager — release scope

> Historical plan. [PRODUCT.md](PRODUCT.md) now defines the intended user, product priorities and acceptance scenarios. Release iterations use v0.0.n until the maintainer is ready for v0.1.0. The original plan below is preserved for context.

20 September 2026. Working descriptive title; public branding remains undecided. This is a build specification, not a claim of implementation or tested compatibility.

## Decision and release promise

Build a standalone graphical system monitor for Omarchy, with Rust application logic and a Qt 6 Quick/QML interface connected through CXX-Qt. Launch independently of the Quattro shell. Use ordinary desktop packaging, not a shell plugin or embedded terminal. Do not fork btop.

The full product should displace btop for local desktop monitoring and process management, and add the app-oriented workflow Windows users expect. Today's v0.1.0 target is a usable daily replacement on Tom's XPS: Apps, Processes and Performance, with honest limits for hardware sensors and ambiguous application ownership. Complete btop feature parity across hardware is a later acceptance milestone. A GUI cannot replace btop's SSH/TTY use when the graphical session is unavailable.

Shipping today is a target contingent on the gates below. If the package or live action tests fail, issue a development build and keep the release untagged. Do not compress verification of process termination to meet the date.

## Primary workflows

1. My laptop is slow: open the app, see CPU/RAM/disk/network activity, sort apps by resource usage, inspect the responsible processes.
2. An app has frozen: find its recognisable name and icon, request Close, then explicitly Force Quit if necessary, with a preview of affected processes.
3. I need technical detail: switch to Processes, search a name or PID, inspect command, user, parent, state, CPU, memory and readable I/O counters.
4. What changed: follow short, bounded live histories and distinguish unavailable, stale and genuinely zero readings.

## Scope matrix

| Area | Required for v0.1.0 | Full displacement follow-through |
| --- | --- | --- |
| Apps | Recognisable names/icons, windows, conservatively assigned processes, CPU and memory aggregates, focus window, Close, Force Quit | Better coverage of Flatpak, Wine, wrappers and independently launched helpers |
| Processes | Flat and tree views; search; stable sorting; PID, user, CPU, resident memory, state; details; Terminate/Force Kill for owned processes | Pause/resume, priority changes, advanced signal selection and narrowly authorised privileged actions |
| CPU | Total/per-core graphs, core count, load and uptime | Additional clocks and temperature coverage |
| Memory | Used/available/total, cache context, swap, live graph | Memory pressure and more detailed accounting |
| Disks | Mounted volume capacity plus block-device read/write rates, clearly separated | Extra device metrics and richer per-process attribution |
| Network | Per-interface receive/transmit rates and totals | Per-app traffic attribution; no privileged tracing in v0.1 |
| GPU | Detect support; show available metrics only if the adapter is implemented and verified; otherwise explicit unavailable state | Intel, AMD and NVIDIA utilisation, memory and temperature support with device-specific evidence |
| Battery/sensors | Battery percentage/charging and temperature when readable; missing sensors never block startup | Broader sensor and multi-battery support |
| Interface | Omarchy colours, light/dark themes, keyboard and mouse, persisted preferences, accessible labels and visible focus | Further assistive-technology coverage, localisation, custom layouts |
| Startup/services | Outside today's release | Startup entries and user services first; system services behind explicit authorisation |

GPU and temperature adapters are the first features to defer today. App identification, correct metrics, responsive lists and safe actions are not optional cuts. Unsupported GPU readings mean we describe v0.1 as an everyday desktop replacement, not universal btop parity.

## Interface contract

One window, three navigation entries: Apps, Processes, Performance. Default to Apps with a compact CPU/memory summary. Use a dense sortable table, search field, selected-item details and labelled actions. Performance has CPU, memory, disks, network and available hardware sections. Avoid a wall of decorative dashboard cards.

Apps columns: name, CPU %, memory and process count. Expand a row to inspect attributed processes and windows. Unknown ownership stays visible in Processes. Never hide an unattributed process to make the Apps page look complete.

Ctrl+F focuses search; keyboard navigation and context menus offer the same actions as mouse controls. Destructive actions require explicit activation; Delete never immediately kills. Escape dismisses menus/dialogs. Sorting and refresh preserve selection by identity, not row number. Pause freezes displayed data; it does not suspend processes, and action targets are always refreshed.

Close requests a normal close for the listed windows, allowing save prompts. Force Quit names the app and affected processes, warns about unsaved work, and requires confirmation. Do not infer “Not responding” from high CPU usage or a Linux sleeping state.

## Implementation and ownership

Use a small Rust project with modules before introducing multiple crates. Main constructs the application session and adapters. The session owns sampling, selection identities, bounded history and shutdown. Core modules handle deltas, grouping, sorting and action policy. QML presents models and invokes commands. OS adapters own /proc, /sys, Hyprland IPC, desktop-file/icon resolution, theme reads and settings writes. No blocking collection in the UI thread.

Start with sysinfo for supported host/process data, supplementing with narrow Linux adapters for missing metrics. Verify each field against the pinned library version. Qt Quick supplies standard controls, scalable rendering and keyboard/accessibility foundations; accessibility still needs testing. CXX-Qt is a documented Rust/Qt bridge, not an Omarchy requirement. Pin a mutually compatible released toolchain after the first build spike; this scope does not invent dependency versions.

The first vertical slice must build into an Arch package and launch a Wayland window showing live CPU, memory and processes. If Rust/Qt integration is a material blocker, re-evaluate the toolkit before expanding the app; do not maintain two UI implementations.

Worker snapshots use monotonic timestamps and bounded queues; discard superseded updates. Sample once per second by default, retaining 60 samples for one minute of context. Support 0.5/1/2/5-second refresh intervals. Pause or throttle collection when hidden, mark discontinuities on resume and never calculate rates across suspend as ordinary intervals. No resident daemon after exit. Cancel and join workers during bounded shutdown.

Settings: XDG configuration directory, versioned data, atomic writes, graceful recovery from malformed files. Persist page, columns, sort, refresh and window preferences. Keep live histories in memory. No accounts, network dependency or telemetry.

## Correctness rules

- A process identity includes PID and start time. Revalidate before acting and use pidfds where supported; never act on a recycled PID. Tests must cover a process exiting between selection and action.
- Resolve apps using Hyprland client information, desktop metadata and genuinely app-specific cgroups. Names alone are not proof of ownership. Parent/child links are supporting evidence, not permission to kill every descendant of a shell.
- Separate visual grouping from termination targets. Shared browser runtimes or uncertain helpers must not be silently swept into Force Quit. Preview a fixed validated target set and report partial failures. A process spawned after that snapshot may survive; do not repeatedly chase descendants.
- Block destructive actions against PID 1, this monitor and identified critical desktop/session components. Run as the user. Other users' processes can be visible when permitted but actions stay disabled in v0.1; no sudo relaunch of the GUI.
- Distinguish Close (window request), Terminate (SIGTERM) and Force Kill (SIGKILL). Never automatically escalate Terminate into Force Kill.
- Show CPU as percent of total machine capacity consistently in default lists; document the convention. Do not compare this directly with tools that use 100% per core. First-sample rates are pending, not fabricated zeroes.
- Label application memory as summed resident memory and explain shared pages may be counted more than once. System memory used must not treat reclaimable cache as unavailable.
- Disk and network counters require deltas over elapsed monotonic time. Handle reset, hotplug, permissions and disappearing devices. Capacity by mount and throughput by device are different measurements; avoid double-counting partitions and parent devices.
- Missing GPU/sensor/process data displays unavailable or permission denied. Retain a last-known sample only with a visible stale indication. Command lines appear in details, not default logs or screenshots intended for publication.

## Desktop and packaging

Use stable proposed identity io.github.tcballard.TaskManager and package/executable omarchy-task-manager, subject to a collision check before repository creation. Install desktop entry and scalable icon; Terminal=false. App ID must match its launcher and window identity. Reopening focuses the existing window.

Read the current Omarchy theme through an isolated adapter and react to theme changes. Confirm actual theme files on the target revision before coding; do not assume undocumented tokens. Use a readable fallback, including light-theme contrast. Test Familiar explicitly.

Propose Ctrl+Shift+Escape as an opt-in shortcut after inspecting existing bindings. Supply a reversible user-level configuration step. Installing must not rewrite Omarchy-owned configuration, remove btop, claim package-manager replacement of btop, or seize an existing shortcut. Making this the upstream default is a separate contribution.

Release initially for verified x86_64 Arch/Omarchy only. Include pinned source, Cargo.lock, licence/attributions, PKGBUILD, checksummed package asset and release notes. Declare Qt/Wayland runtime dependencies; do not bundle toolchains. Review package and installed size. Store/package-repository admission is separate from releasing the application and cannot be promised today.

## Build sequence for today

| Gate | Deliverable | Evidence required before proceeding |
| --- | --- | --- |
| 1. Foundation | Rust/Qt window, live host/process data, basic Arch package | Clean build and a real Wayland launch; validate dependency/toolkit choice |
| 2. Monitoring | Processes and Performance complete | Fixture-based metric tests and live comparison with /proc and existing monitors |
| 3. Application workflow | Apps, identity matching, focus/close/kill | Dedicated test apps; ambiguous ownership and PID-reuse tests; no collateral termination |
| 4. Desktop polish | Theme adaptation, icons, launcher, keyboard/mouse and preferences | XPS launch, Familiar/light/dark, scaling and input checks |
| 5. Release | Package, README, screenshots, known limitations and v0.1.0 assets | Clean Arch package checks plus XPS acceptance below; green CI |

Suggested PR boundaries follow these five gates. Each should build independently. Effort cannot be responsibly estimated as a fixed number of hours before gate 1; hardware adapters and identity edge cases are the main schedule risks.

## Required verification

Automated: counter reset and first sample; CPU convention; shared-memory labelling; tree cycles/orphan processes; filtering and stable selection; stale snapshot rejection; ambiguous grouping; protected targets; PID reuse; permissions; malformed config; worker cancellation. Use spawned disposable test processes for termination tests, never arbitrary host processes.

On Tom's XPS: launch from the launcher without a terminal; open terminal-launched and launcher-launched apps; inspect a multiprocess browser; sort while processes appear/disappear; close an editor with an unsaved document and observe its prompt; force-kill only a disposable app that ignores termination; verify the browser/session remains intact; test theme switching, 100% and actual display scaling; suspend/resume and network changes; reopen/focus; install and uninstall the built package.

Measure the monitor's own CPU/RSS, startup and interaction behaviour. It should not noticeably worsen the slowdown it is diagnosing. Proposed investigation thresholds on the XPS: sustained idle monitoring above 2% of one CPU core or RSS above 150 MiB; these are engineering targets to validate, not promised measurements. Bound histories and virtualise long lists; investigate growth during an extended run. Compare approximate metrics over matching intervals, not identical instantaneous numbers from differently timed tools.

No live desktop or package validation has been performed as part of this scope. CI success alone does not satisfy these release gates.

## Evidence and alternatives

- [btop](https://github.com/aristocratos/btop): process trees, filtering, signals, CPU/memory/disk/network monitoring, GPU support and terminal/mouse UI establish the displacement baseline. Reimplementing a graphical UI around its internals does not automatically provide desktop-app identity.
- [Resources](https://github.com/nokyan/resources): existing Rust GTK4/libadwaita monitor with graphical app management. Its GitHub README points to continued development in GNOME GitLab; the archived mirror is not evidence of an abandoned project. Useful comparison, but a GNOME-oriented fork would require replacing much of its UI for this brief. This was a README-level review, not a code-reuse audit.
- [CXX-Qt](https://kdab.github.io/cxx-qt/book/) and [Qt Wayland](https://doc.qt.io/qt-6/wayland-and-qt.html): support the proposed integration approach; do not prove this unbuilt application's compatibility.
- [sysinfo](https://docs.rs/sysinfo/latest/sysinfo/) and [Hyprland IPC](https://wiki.hypr.land/IPC/): candidate metric and desktop integration interfaces. Verify pinned APIs during implementation.
- [Develop for Omarchy](https://omarchyapps.com/develop): unofficial packaging checklist covering desktop launch, dependencies and install/uninstall validation; upstream repository rules take precedence at submission.

The installed Omarchy app design skill incorporates lessons from OmaCut about ownership and adapters. OmaCut source could not be freshly retrieved in this session, so this is not a new source audit or a claim of a mandatory upstream stack. Mission Center retrieval also failed; no unsupported claim about its current suitability is used here.
