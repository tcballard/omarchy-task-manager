# Architecture

The standalone Qt Quick GUI owns a Rust worker. A private newline-delimited JSON pipe connects them. Closing the panel closes its worker; there is no resident collector or background service. The GUI stays unprivileged. No Quickshell singleton is imported outside its host.

## Boundaries

- `src/process.rs`: procfs processes and stable PID/start identities; ownership/session protection; pidfd signaling; Linux thread priority and affinity.
- `src/metrics.rs`: sampled CPU/memory/disk/network counters, discontinuity handling, capacity and sensors.
- `src/gpu.rs`: deduplicated DRM clients, AMD sysfs and optional NVIDIA device counters. Missing data remains unknown.
- `src/desktop.rs`: Hyprland IPC, window/app attribution, desktop launchers, theme files, placement of the worker's own parent GUI window.
- `src/manage.rs`: service/session actions, startup overrides, process inspection and optional core dumps.
- `src/slow.rs`: one bounded background filesystem-capacity collector, with stale-data expiry.
- `src/bounded.rs`: bounded text reads and response serialization.
- `src/command.rs`: bounded, deadline-controlled command capture and cancellation of its active process group.
- `src/storage.rs`: private same-directory atomic writes, with owned temporary-file cleanup.
- `src/desktop_entry.rs`: shared Desktop Entry parsing for launcher discovery and autostart.
- `src/history.rs`: bounded per-executable sampled history and periodic atomic persistence.
- `ui/bridge.*`: worker lifecycle, stable-key selection, filtering/sorting, fixed confirmation targets, Qt preferences, launch/copy/export.
- QML: presentation, floating-window chrome, keyboard/mouse controls, graph history and dialogs.

## Action contract

The confirmation records exact process identities; it never silently expands a group when accepted. Signals open a pidfd, reread process identity and ownership, check protected processes/ancestors, then send through that descriptor. Group actions share one protection snapshot rather than rescanning procfs for every member; the current critical executable is also checked for each target. Tree actions show the descendants captured at preparation time. Partial failures are visible.

Nice and affinity use Linux's numeric thread-ID APIs, which do not accept a pidfd. The worker checks leader and thread start times immediately before each operation; this reduces but does not eliminate a concurrent exit/PID-reuse race. Changes apply to existing threads and report completed and failed counts, including threads that disappear during enumeration or revalidation; the first eight errors are retained. Optional gcore likewise uses a numeric PID and validates before/after capture; it is subject to ptrace permissions and removes output if post-capture identity cannot be verified. These paths must not be described as having pidfd-level guarantees.

Application restart requires a known desktop launcher, validates all captured targets, sends SIGTERM, waits up to three seconds for exit, and launches through GLib's desktop-entry implementation. Failure to exit does not trigger an automatic kill. Closing an app window is a compositor request and may present a save prompt.

System commands use fixed executable paths, validated unit/session identifiers and argument arrays, with no shell interpretation. Four-second deadlines bound management reads and service actions. Commands may continue inside systemd even if a client times out; the next refresh is authoritative. Core capture has a 60-second deadline. Captured stdout is limited to 8 MiB and stderr to 64 KiB while reading. Worker SIGTERM cancels active captured commands, kills their process group before reaping the leader, and allows history persistence; forced SIGKILL cannot provide graceful cleanup. The GUI allows 15 seconds per normal worker request and 65 seconds for capture. A worker timeout leaves an explicit error and requires relaunch.

## Sampling and state

System/process samples default to one second. CPU uses whole-machine capacity. The first sample, counter resets, long sampling gaps and suspend discontinuities do not invent rate values. Histories retain 60 seconds and are invalidated on discontinuity. Explicit pause transitions reset the next sample baseline even for a short gap; an in-flight pre-pause response is discarded. Sampling continues at the selected interval while the running window is hidden, minimized, unfocused or on another workspace. Visibility changes do not reset graph history. Detailed sampling pauses explicitly or in an action confirmation; quitting stops this worker but leaves the basic collector running. Inspection and long management actions occupy the worker; the panel remains responsive but live readings wait.

Filesystem capacity (`statvfs`) runs on one background thread with bounded channels. At most one request is outstanding; a stalled syscall never spawns replacement collectors or holds up process snapshots. Capacity refreshes every five seconds and is hidden as unavailable after fifteen seconds without a completed result. A permanently stuck collector stays unavailable until relaunch; other metrics continue. This does not make arbitrary kernel/filesystem I/O cancellable.

GPU client attribution stats each process descriptor and reads fdinfo only for DRM and accel character devices. When the NVIDIA driver and `nvidia-smi` are present, one long-running query streams device counters every second instead of a new query per sample; NVML initialisation dominates the cost of each spawn. Its lines are bounded, readings older than three seconds are withheld, and an exited query restarts at most every ten seconds. The main sampling thread spawns it with a parent-death signal, and the worker kills and reaps it on exit.

Inspection bounds file lists to 256 directory entries, threads to 512, maps to 512 KiB, status/cgroups to 64 KiB each, and process command lines to 16 KiB. Truncation is disclosed. Serial request handling tracks whether inspection is pending and still displayed. Errors appear inside the inspector; completion updates data without reopening a dismissed dialog. Outgoing JSON is serialized into a 16 MiB bounded buffer before any frame is written. Oversized results become an error frame; the GUI retains its last complete sample and the next request can recover. This bounds serialization, not the entire in-memory process inventory.

Service/startup/session inventory is page-specific, with a five-second cache invalidated after actions. A management snapshot includes its page identity so another page cannot briefly expose stale actionable rows. All process rows are available independently of desktop-window attribution.

Usage history groups the current user's processes by executable, accumulates deltas only across continuous samples, stores at most 4096 executable keys, and writes every 30 seconds/normal exit. Unreadable saved history is preserved until explicit reset, persistence errors are visible, and a failed reset retains the in-memory rows. UI preferences use QSettings. Startup edits preserve other desktop-entry sections and atomically write a same-directory per-user override. Core dumps have per-capture directories with mode 0700. No upload or analytics is performed.

## Desktop and theme

Stable app/window ID: `io.github.tcballard.TaskManager`. A per-user local socket activates an existing instance. If Unix sockets are prohibited, launch still works under a lock but repeat activation reports failure. The GUI requests floating/size/position only for its own parent PID's matching window. No global compositor rules or bindings are changed.

The monospace family follows fontconfig. `colors.toml` provides a complete validated background/foreground/accent set. Supported flat `shell.toml` keys cover popup colors, typography and selected control fills/widths. This is a deliberately bounded parser for these tokens, not a complete TOML engine or implementation of all Quattro gradients/spacing/radii. Reads survive atomic theme-directory replacement. Changes apply on the next active sample. Shared QML helpers validate finite font/control values and clamp ranges. The panel fits the available logical screen; oversized content and table columns scroll, and the close button remains fixed. Enlarged text increases workspace, table and row dimensions. Physical monitor placement and scaling still require live acceptance.

## Validation boundaries

Portable tests cover real procfs and disposable process actions, temporary startup/history files, protocol failures, and the rendered Qt interface. Live compositor tests, systemd service mutation, session termination, GPU adapters, Arch packaging and real-monitor behavior require the target environment. See VERIFICATION.md; do not infer those outcomes from offscreen screenshots.

## Independent background history

`omarchy-task-manager-core --monitor` is a separate systemd user service enabled at the first normal installed launch. It reads basic procfs CPU/memory/network/disk counters every second, without process enumeration, compositor IPC, GPU tools, filesystem capacity calls or service queries. The asynchronous UI service controller bounds systemctl requests at eight seconds, then allows five seconds for fresh, locked collector history before reporting startup success. It persists successful setting changes and reports failures. Closing the UI leaves the service running. Disabling Background monitoring disables and stops it; subsequent launches retain that choice. No root daemon, login lingering or network listener is installed.

The service holds a nonblocking exclusive flock in an owner-checked private XDG runtime directory. It atomically replaces a mode-0600 versioned JSON ring (at most 61 points / 60 seconds / 2 MiB). Readers require a live lock, valid schema/order and data no older than three seconds. Crash leftovers are ignored. Clean stop deletes the cache before releasing the lock; restart begins a new baseline. Suspend/clock discontinuities clear the ring. Sequential start-to-start collection has no overlaps or catch-up bursts. SIGTERM is checked every 50 ms between samples; systemd caps shutdown at three seconds. Package binary removal also ends collection on the next iteration.

A new GUI worker imports fresh basic history on its first snapshot. Boot-time timestamps are converted to the local elapsed clock; detailed samples then extend the graphs. Manual pause/resume never reimports old history. GPU and per-app usage are only sampled while the GUI runs. Display pause and action confirmations do not stop the independent collector.
