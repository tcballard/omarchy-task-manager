# Architecture

The standalone Qt Quick GUI owns a Rust worker. A private newline-delimited JSON pipe connects them. Closing the panel closes its worker; there is no resident collector or background service. The GUI stays unprivileged. No Quickshell singleton is imported outside its host.

## Boundaries

- `src/process.rs`: procfs processes and stable PID/start identities; ownership/session protection; pidfd signaling; Linux thread priority and affinity.
- `src/metrics.rs`: sampled CPU/memory/disk/network counters, discontinuity handling, capacity and sensors.
- `src/gpu.rs`: deduplicated DRM clients, AMD sysfs and optional NVIDIA device counters. Missing data remains unknown.
- `src/desktop.rs`: Hyprland IPC, window/app attribution, desktop launchers, theme files, placement of the worker's own parent GUI window.
- `src/manage.rs`: service/session actions, startup overrides, process inspection and optional core dumps.
- `src/command.rs`: bounded, deadline-controlled command capture and cancellation of its active process group.
- `src/storage.rs`: private same-directory atomic writes, with owned temporary-file cleanup.
- `src/desktop_entry.rs`: shared Desktop Entry parsing for launcher discovery and autostart.
- `src/history.rs`: bounded per-executable sampled history and periodic atomic persistence.
- `ui/bridge.*`: worker lifecycle, stable-key selection, filtering/sorting, fixed confirmation targets, Qt preferences, launch/copy/export.
- QML: presentation, floating-window chrome, keyboard/mouse controls, graph history and dialogs.

## Action contract

The confirmation records exact process identities; it never silently expands a group when accepted. Signals open a pidfd, reread process identity and ownership, check protected processes/ancestors, then send through that descriptor. Group actions share one protection snapshot rather than rescanning procfs for every member; the current critical executable is also checked for each target. Tree actions show the descendants captured at preparation time. Partial failures are visible.

Nice and affinity use Linux's numeric thread-ID APIs, which do not accept a pidfd. The worker checks leader and thread start times immediately before each operation; this reduces but does not eliminate a concurrent exit/PID-reuse race. Changes apply to existing threads and report partial failures. Optional gcore likewise uses a numeric PID and validates before/after capture; it is subject to ptrace permissions and removes output if post-capture identity cannot be verified. These paths must not be described as having pidfd-level guarantees.

Application restart requires a known desktop launcher, validates all captured targets, sends SIGTERM, waits up to three seconds for exit, and launches through GLib's desktop-entry implementation. Failure to exit does not trigger an automatic kill. Closing an app window is a compositor request and may present a save prompt.

System commands use fixed executable paths, validated unit/session identifiers and argument arrays, with no shell interpretation. Four-second deadlines bound management reads and service actions. Commands may continue inside systemd even if a client times out; the next refresh is authoritative. Core capture has a 60-second deadline. Captured stdout is limited to 8 MiB and stderr to 64 KiB while reading. Worker SIGTERM cancels active captured commands, kills their process group before reaping the leader, and allows history persistence; forced SIGKILL cannot provide graceful cleanup. The GUI allows 15 seconds per normal worker request and 65 seconds for capture. A worker timeout leaves an explicit error and requires relaunch.

## Sampling and state

System/process samples default to one second. CPU uses whole-machine capacity. The first sample, counter resets, long sampling gaps and suspend discontinuities do not invent rate values. Histories retain 60 seconds and are invalidated on discontinuity. Explicit pause/minimise transitions reset the next sample baseline even for a short gap; an in-flight pre-pause response is discarded. Sampling pauses while hidden/minimized, explicitly paused, or in an action confirmation. Inspection and long management actions occupy the worker; the panel remains responsive but live readings wait.

Service/startup/session inventory is page-specific, with a five-second cache invalidated after actions. A management snapshot includes its page identity so another page cannot briefly expose stale actionable rows. All process rows are available independently of desktop-window attribution.

Usage history groups the current user's processes by executable, accumulates deltas only across continuous samples, stores at most 4096 executable keys, and writes every 30 seconds/normal exit. Unreadable saved history is preserved until explicit reset, persistence errors are visible, and a failed reset retains the in-memory rows. UI preferences use QSettings. Startup edits preserve other desktop-entry sections and atomically write a same-directory per-user override. Core dumps have per-capture directories with mode 0700. No upload or analytics is performed.

## Desktop and theme

Stable app/window ID: `io.github.tcballard.TaskManager`. A per-user local socket activates an existing instance. If Unix sockets are prohibited, launch still works under a lock but repeat activation reports failure. The GUI requests floating/size/position only for its own parent PID's matching window. No global compositor rules or bindings are changed.

The monospace family follows fontconfig. `colors.toml` provides a complete validated background/foreground/accent set. Supported flat `shell.toml` keys cover popup colors, typography and selected control fills/widths. This is a deliberately bounded parser for these tokens, not a complete TOML engine or implementation of all Quattro gradients/spacing/radii. Reads survive atomic theme-directory replacement. Changes apply on the next active sample.

## Validation boundaries

Portable tests cover real procfs and disposable process actions, temporary startup/history files, protocol failures, and the rendered Qt interface. Live compositor tests, systemd service mutation, session termination, GPU adapters, Arch packaging and real-monitor behavior require the target environment. See VERIFICATION.md; do not infer those outcomes from offscreen screenshots.
