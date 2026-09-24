# Task Manager: Windows-to-Omarchy feature map

Status: v0.1.0, the first non-preview release. The maintainer accepted the v0.0.5 application behaviour on the XPS and approved v0.1.0 on 24 September 2026, including Summary, background monitoring, logout/reboot startup and GPU readings. This release changes version labels and documentation, not application behaviour. Other hardware remains unverified; see VERIFICATION.md.

| Familiar Windows capability | Omarchy implementation | Boundary |
|---|---|---|
| Summary | CPU/memory history and top running applications with a route to Applications | No automatic diagnosis; displayed values depend on available samples |
| Processes/app groups | Hyprland windows + descendant groups, full readable process list | Shared helpers, Flatpak/Wine/cgroups not fully attributed |
| End task / end process tree | Confirmed SIGTERM/SIGKILL with fixed PID/start identities | Own processes only; desktop/session protection |
| Switch to / close app | Focus/close a Hyprland window | First window of a group |
| Restart app | Terminate group then launch its matching desktop entry | Known desktop entries; no forced restart after timeout |
| Search / sort / details | Search name, user, PID; sort and choose columns; tree view | No Windows-specific columns |
| CPU/memory performance | Aggregate/per-core history, frequency, RSS, cache, swap, commit counters | Linux accounting and visibility |
| Disk/network performance | Throughput histories, disk activity/latency, volumes, link metadata | No per-process network attribution |
| GPU performance | DRM client counters, AMD sysfs, optional nvidia-smi | Driver-specific support; hardware validation pending |
| Background graphs | User service retains up to 60 seconds of CPU/per-core, memory, disk and network readings after the window closes | One-second cadence; requires installed user service; GPU/per-app history only while the app runs |
| App history | Persistent sampled CPU time/disk bytes/peak RSS by executable | Only while sampling; no UWP/background network accounting |
| Startup apps | XDG per-user enable/disable override | Hyprland scripts opened as configuration; no startup impact score |
| Users | Resource totals and session list, filter processes, lock/sign out | Own-session controls; no administrator impersonation |
| Services | User/system service inventory, lifecycle, enable/disable, journal | Systemd permissions; protected session services |
| Run new task | Direct executable and argument launch | Current user; no shell evaluation/elevation checkbox |
| Set priority / affinity | Linux nice and CPU sets for existing threads | Kernel permissions; numeric-TID API limitations |
| Efficiency mode | Explicit lower-priority action | No EcoQoS or hardware power promise |
| Suspend / resume | pidfd SIGSTOP/SIGCONT | Own unprotected processes |
| File location / properties | Executable folder, commands, status, cgroup, maps, open FDs | Permission-restricted information can be absent |
| Wait-chain diagnostics | Per-thread kernel wait channels | No deadlock detection or Windows wait-chain API |
| Create dump | Optional gcore into private directory | gdb + ptrace permission; 60-second limit |
| Update speed / pause | 0.5/1/2/5 seconds, pause/resume | Live-view pause; separate background collection toggle |
| Copy / export | Copy details, save JSON snapshot | Local files only |
| Compact floating surface | Frameless Hyprland float, drag, Escape, stay-open/blur-dismiss | Standalone window; no bar anchor or layer-shell |
| Omarchy theme/font | Monospace alias, semantic palette, shell font sizes and selected control tokens | Solid border; not every shell gradient/spacing/radius token |

The application deliberately does not translate Windows-only kernel concepts into fabricated Linux measurements. Universal btop parity, root-level controls, per-process network attribution and complete Quattro style-token parity are not claimed.
