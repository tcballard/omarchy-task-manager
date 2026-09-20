# v0.1.0 hardening review

Reviewed 20 September 2026 against `b7edec23deab8f891a1a62a2842570948767985e` (`origin/main`). Scope: every Rust module, Qt bridge and application lifecycle, QML pages, existing tests, build, desktop entry and package recipe. This is a code review and portable hardening pass, not live Omarchy acceptance or a release certification.

The findings below refer to the baseline implementation. Fixes and regression coverage are included in this branch. The previous README opening and social-card edits are separate work and are not included.

## Findings addressed

| Priority | Finding and user impact | Fix and evidence |
| --- | --- | --- |
| P1 | `history.rs`: malformed saved JSON was silently treated as empty history and overwritten during shutdown. | Preserve an unreadable file until an explicit reset. Surface the error on App history. Real temporary-file test verifies preservation across destruction/reopen and explicit recovery. |
| P2 | `manage.rs::atomic_write`: a predictable temporary filename collided with stale/concurrent writes; failed `create_new` then removed a file this write did not create. | Shared `storage.rs` creates unique same-directory files, cleans only files it owns, syncs the file and directory. Tests cover concurrent complete writes, pre-existing temporary files, permissions and a failed rename. |
| P2 | `history.rs`: periodic persistence failures were discarded; reset cleared memory before checking that disk persistence succeeded. | Visible save errors; reset writes first, then updates memory. A failed-reset fixture verifies retained rows. |
| P2 | `gpu.rs`: removing all NVIDIA rows inside the CSV loop meant only the last NVIDIA GPU remained. | Parse the NVIDIA response first, then replace the NVIDIA adapter set once. Two-device and mixed-vendor fixtures pass; malformed responses preserve fallback rows. |
| P2 | `gpu.rs`: holding each DRM counter at its historical maximum froze usage at zero after a driver counter reset. | Use the shared checked-delta calculation; reset produces unknown, and the next sample uses the new baseline. Counter-reset/capacity regression passes. |
| P2 | `bridge.cpp` / `metrics.rs`: pauses or minimisation shorter than 15 seconds were treated as continuous sampling, including paused activity in resumed rates and usage history. | Explicit baseline reset on resume; discard an in-flight pre-pause sample. Qt tests cover pause, hiding and pause/resume while a response is pending; protocol test verifies unknown first rates. |
| P2 | `manage.rs::run`, `main.rs`, `history.rs`: size checks happened after collecting command output, an entire request line or an entire history file. | Bound reads while allocating. Shared nonblocking command capture bounds stdout/stderr and enforces deadlines. Tests cover stdout/stderr floods, timeout, bounded request consumption and malformed history. |
| P2 | `manage.rs::dump`: killing a busy worker could leave its external debugger command running. | Core capture uses the shared cancellable command runner. SIGTERM stops the active command group, reports capture failure and permits cleanup/final history persistence. Tests cover cancellation and idle-worker SIGTERM with stdin still open. Actual gcore/ptrace capture still needs the target. |
| P2 | `Main.qml`: confirmation preparation and pause bookkeeping were duplicated in three paths; re-entry could replace pending state and restore the wrong paused state. Application shortcuts were not explicitly disabled over modal dialogs. | One confirmation function plus modal shortcut guards. Qt regression verifies page/new-task/Delete shortcuts and repeated `ask()` cannot alter an open confirmation, and cancellation restores monitoring. |
| P2 | QML labels and confirmation text used automatic rich-text detection on externally supplied names and messages. Markup-like process names could change how the target was displayed. | Shared `PlainLabel` and plain button text; explicit plain confirmation header/body. Qt test checks literal image markup in confirmation content. |
| P2 | `process.rs` / `main.rs`: a fixed group action rescanned all processes for every member, making tree termination scale with group size × system process count. Restart could also abort when a child had already exited during group shutdown. | One protection snapshot per batch; each target still opens a pidfd and revalidates identity, owner and critical executable. Mixed valid/stale/protected target test passes. Restart tolerates already-exited original members. No target-hardware performance claim. |
| P3 | `bridge.cpp`: management preparation lacked category/page checks, and a rejected tree request could leave a hidden pending action. | Validate category/page/eligibility and clear rejected pending work. Qt tests cover wrong-page management requests. |

P1 means potential loss of retained user data; P2 means incorrect behavior or a meaningful reliability/safety gap; P3 means defensive consistency. These are review priorities, not vulnerability or CVSS ratings.

## Duplication removed

- Desktop Entry parsing is shared by launcher discovery and autostart, with one policy for whitespace, comments and section boundaries. Previously the two parsers disagreed.
- Atomic persistence lives in `storage.rs`; history no longer depends on the management-action module for writing files.
- Bounded system-command capture and cancellation live in `command.rs`, shared by service/session commands, GPU queries and core capture.
- The three C++ page-name validation lists now have one owner in `Bridge`.
- The production and test executables share one QML resource list, including the new plain-text component.
- Confirmation setup is shared across process, tree and management actions. GPU engine rates reuse the counter-reset logic already used for other metrics.

## Follow-up findings and deliberate limits

| Priority | Remaining finding | Recommended next action |
| --- | --- | --- |
| P2 | `Bridge::inspect` opens a loading dialog, but a worker error only updates the footer. Closing the dialog before completion can allow its eventual response to reopen it. | Give inspection requests a completion/cancellation identity, show errors in the dialog, and test dismiss-during-load. Current process mutation targets remain separately pinned. |
| P2 | `process.rs::tune` can return early on a disappearing thread after modifying earlier threads, without reporting the partial count. Numeric-TID nice/affinity and numeric-PID gcore still have the documented reuse race. | Improve partial-result reporting and test thread churn. Do not describe these controls as having the same guarantees as pidfd signals. |
| P2 | `metrics.rs::mounts` uses synchronous `statvfs`; a stalled filesystem can occupy the worker. Procfs inspection and the complete outgoing snapshot also remain capable of exceeding the GUI response cap on very large workloads. | Separate slow filesystem work and bound inspection payloads; exercise large process/FD inventories and stalled-device behavior. The GUI watchdog currently requires a relaunch after a worker stall. |
| P2 | Floating placement enforces an 850 × 560 minimum even on a smaller logical monitor; optional columns can exceed the available table width. Theme font tokens lack complete finite/range validation. | Test the XPS at its actual scaling, multiple monitors and enlarged fonts; add size-aware layout and malformed-token cases before claiming broad scaling support. |
| P3 | `Main.qml` and `bridge.cpp` still combine several responsibilities. Process and management tables duplicate column layout, sorting headers and row interaction; `/proc/diskstats` is parsed twice per sample, and state-directory resolution is duplicated. | Extract a shared resource table and performance page in a separate PR, then introduce typed protocol structures where they remove repeated string-key assumptions. Consolidate disk parsing and XDG paths with fixtures. Avoid a framework rewrite immediately before v0.1.0. |
| P3 | Application metadata is loaded once and scans only the top-level applications directories. | Add recursive desktop-file ID handling and refresh/invalidation; test applications installed while the panel is open. Existing Flatpak/Wine attribution limits remain. |

## Verification

Platform: Ubuntu 24.04 x86_64; Rust 1.98.1; GCC 13.3; Qt 6.4.2. The input manifest is `HARDENING.sha256`. The older `VERIFICATION.md` and `EVIDENCE.sha256` remain historical evidence for their original inputs.

| Check | Result on the manifested inputs |
| --- | --- |
| `cargo fmt --check` | Passed. |
| `cargo clippy --locked --all-targets -- -D warnings` | Passed. |
| `cargo test --locked` | Passed: 30 Rust tests (baseline had 17). |
| CMake Release build (`cmake --build build -j 4`) | Passed; GUI, worker and both Qt test executables built. |
| `ctest --test-dir build --output-on-failure` | Passed: both bridge and rendered offscreen UI suites. |
| `python3 tests/protocol.py build/omarchy-task-manager-core` | Passed for real procfs, disposable actions, startup/history and SIGTERM persistence. Compositor IPC cases explicitly skipped because this host blocks Unix sockets. |
| `desktop-file-validate packaging/io.github.tcballard.TaskManager.desktop` | Passed. |
| `clang-format --dry-run --Werror` on changed C++ files | Passed. |
| `git diff --check` and PR mechanical preflight | Passed (proposed work was uncommitted at the initial preflight). |
| `scripts/package-source.sh` | Passed; archive contains every new source/QML file and review manifest, and its SHA-256 matches the generated recipe. This is not an Arch package build. |
| Staged `/usr` installation, then installed GUI `--smoke` under fresh XDG paths | Passed with offscreen/software Qt; worker located in the installed `usr/lib/omarchy-task-manager` directory. Local activation sockets unavailable. |
| `sha256sum -c HARDENING.sha256` | Passed. |
| Live Omarchy/Hyprland, GPU hardware, real systemd/session actions, actual gcore capture, Arch install/upgrade/removal | Not run: this Ubuntu environment has no target desktop/GPU, gcore or Arch package manager. |

Iteration failures were resolved before this final gate: a missing QSignalSpy include and a Rust function-pointer cast lint. The first installed-GUI smoke attempt found an empty local GUI build artifact and failed with an exec-format error; recompiling/relinking the unchanged GUI source produced a verified ELF binary and the repeated installed smoke passed. The cause of the empty local artifact was not established. CI must independently build and smoke-test the PR head. No failed or skipped check is counted as a pass.

## Release decision

This branch improves the preview and makes the remaining risks explicit. It does not authorize or create a v0.1.0 tag. Before release, run the README's live XPS acceptance, GPU comparisons, service/session controls, actual core capture, and Arch install/upgrade/removal. Check CI for the exact PR head. Review the remaining P2 findings against the intended v0.1.0 promises; portable tests alone do not close them.
