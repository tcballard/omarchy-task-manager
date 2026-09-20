# v0.1.0 hardening review

> Historical record: this work used the planned v0.1.0 label. The first published preview is v0.0.1; we will iterate through v0.0.n before v0.1.0. Existing evidence and hashes describe their original inputs, not the release commit. Release CI supplies fresh build results and asset checksums.

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

## Second pass: failure recovery and layout

Continued from PR #1 commit `54b8cc315999cbd72d949956a87774490add98d4`, whose Ubuntu and Arch build/test CI passed. This pass addresses the four remaining P2 implementation findings:

| Area | Change and regression evidence |
| --- | --- |
| Inspection lifecycle | Explicit pending/displayed state under the existing single-request protocol. Open only when requested, show request/worker errors inside the dialog, ignore dismissed results. Qt tests cover a real invalid identity, dismissal, a late successful reply and worker failure. Empty journals have an explicit message. |
| Partial thread tuning | Preserve enumeration, identity and syscall failures without returning before reporting earlier changes. Report successful/failed counts and bounded error details; reject an empty thread set. Deterministic fixture mixes success, disappearance and permission failure; protocol tests still exercise real nice/affinity changes. Numeric-TID/PID reuse remains a documented platform limitation. |
| Filesystems and large responses | One background capacity collector with bounded channels and no replacement thread accumulation. Hide stale capacity after 15 seconds while process sampling continues. Bound inspection lists/text and command lines; disclose truncation. Bound response serialization to 16 MiB, return an error frame on overflow, and accept the next request. Fixtures cover a blocked collector, 300 real open file descriptors, bounded text reads and oversized-response recovery. |
| Panel sizing and theme inputs | Fit logical monitor bounds, keep the close button fixed, and expose scrolling for oversized workspace/table content. Share table sizing/viewport and finite/range-checked numeric tokens. Scale rows with body text. Qt tests cover 640 × 480, all optional columns, 24 px text, invalid/infinite/negative/extreme tokens and scroll reachability. Rust tests cover small monitor placement dimensions. These are offscreen tests, not live monitor acceptance. |

The file-inventory stress test initially caught a missing truncation notice when an enumerated FD disappeared before `readlink`; the limit now counts directory entries and always discloses reaching the cap. Final verification below uses the corrected implementation. An offscreen visual check also prompted keeping Close outside the scrolling header.

CI now checks the staged installed binary on Ubuntu, plus Arch package install, same-version reinstall, unprivileged installed smoke and removal. Reinstallation is not evidence for upgrading from a prior released version.

## Follow-up findings and deliberate limits

| Priority | Remaining finding | Recommended next action |
| --- | --- | --- |
| P3 | `Main.qml` and `bridge.cpp` still combine several responsibilities. Process and management tables still duplicate sorting headers and row interaction (column sizing and horizontal viewports are now shared); `/proc/diskstats` is parsed twice per sample, and state-directory resolution is duplicated. | Extract a shared resource table and performance page in a separate PR, then introduce typed protocol structures where they remove repeated string-key assumptions. Consolidate disk parsing and XDG paths with fixtures. Avoid a framework rewrite immediately before v0.1.0. |
| P3 | Application metadata is loaded once and scans only the top-level applications directories. | Add recursive desktop-file ID handling and refresh/invalidation; test applications installed while the panel is open. Existing Flatpak/Wine attribution limits remain. |

## Verification

Platform: Ubuntu 24.04 x86_64; Rust 1.98.1; GCC 13.3; Qt 6.4.2. The current second-pass input manifest is `HARDENING.sha256`; first-pass evidence and its original manifest remain in commit `54b8cc315999cbd72d949956a87774490add98d4`. The older `VERIFICATION.md` and `EVIDENCE.sha256` remain historical evidence for their original inputs.

| Check | Result on the manifested inputs |
| --- | --- |
| `cargo fmt --check` | Passed. |
| `cargo clippy --locked --all-targets -- -D warnings` | Passed. |
| `cargo test --locked` | Passed: 36 Rust tests (baseline had 17; first hardening pass had 30). |
| CMake Release build (`cmake --build build -j 4`) | Passed; GUI, worker and both Qt test executables built. |
| `ctest --test-dir build --output-on-failure` | Passed: both bridge and rendered offscreen UI suites. |
| `python3 tests/protocol.py build/omarchy-task-manager-core` | Passed for real procfs, disposable actions, startup/history and SIGTERM persistence. Compositor IPC cases explicitly skipped because this host blocks Unix sockets. |
| `desktop-file-validate packaging/io.github.tcballard.TaskManager.desktop` | Passed. |
| `clang-format --dry-run --Werror` on changed C++ files | Passed. |
| `git diff --check` and PR mechanical preflight | Passed (proposed work was uncommitted at the initial preflight). |
| `scripts/package-source.sh` | Passed; archive contains every new source/QML file and review manifest, and its SHA-256 matches the generated recipe. This is not an Arch package build. |
| Staged `/usr` installation, then installed GUI `--smoke` under fresh XDG paths | Passed with offscreen/software Qt; worker located in the installed `usr/lib/omarchy-task-manager` directory. Local activation sockets unavailable. |
| `sha256sum -c HARDENING.sha256` | Passed. |
| Live Omarchy/Hyprland, GPU hardware, real systemd/session actions, actual gcore capture, target-machine install/upgrade/removal | Not run: this Ubuntu environment has no target desktop/GPU, gcore or Arch package manager. |

First-pass iteration failures were resolved before that gate: a missing QSignalSpy include and a Rust function-pointer cast lint. The first installed-GUI smoke attempt found an empty local GUI build artifact and failed with an exec-format error; recompiling/relinking the unchanged GUI source produced a verified ELF binary and the repeated installed smoke passed. The cause of the empty local artifact was not established. CI must independently build and smoke-test the PR head. No failed or skipped check is counted as a pass.

## Live service integration gate

`tests/live_services.py` runs on the Ubuntu CI VM against real systemd. It creates a unique disposable unit, then drives the production worker protocol through inventory, start, restart (verified by a changed invocation ID), journal retrieval, enable, disable and stop. It checks desktop-service protection, a denied system-service mutation as `nobody`, and fixture cleanup. System scope runs only as root in CI; user scope runs under a dedicated unprivileged account with its own user manager. This tests backend controls and actual service outcomes, not the Omarchy polkit interaction or GUI on the XPS.

The local container has neither a GPU device nor a running systemd manager. These live checks are deliberately separate from portable tests and fail if their required manager is unavailable; they do not silently skip. Physical GPU accuracy, Omarchy session controls and target-specific authorization remain live-target gates.

## Release decision

This branch improves the preview and makes the remaining risks explicit. It does not authorize or create a v0.1.0 tag. Before release, run the README's live XPS acceptance, GPU comparisons, service/session controls, actual core capture, and Arch install/upgrade/removal. Check CI for the exact PR head. The P2 code findings from the first pass are addressed; portable tests do not establish live desktop reliability. Before calling this release-ready, record the following against the exact candidate:

- Real XPS/Omarchy: open/activate/close repeatedly, pause/minimise/resume, switch themes, fractional scale and multiple monitors; confirm all controls remain reachable.
- Disposable workloads: rapid process/thread churn, protected processes, permission failures, terminate/tree/restart, priority/affinity and actual gcore capture with shutdown cancellation.
- Desktop services: user/system service and journal behavior, session lock/logout, startup enable/disable and persistence across login.
- Compare CPU/disk/network/GPU readings on available hardware, including idle/load transitions and suspend/resume; run an extended monitoring session and check memory/CPU overhead.
- Install/remove the produced Arch artifact on the target and preserve user state across reinstall. No prior released version exists for a genuine upgrade test yet.

No live-target result is claimed here. A blocked capacity collector deliberately remains unavailable until relaunch; other kinds of stalled worker I/O still use the explicit relaunch watchdog. Recursive launcher discovery/metadata refresh and broader table/page decomposition remain follow-ups, not completed work.
