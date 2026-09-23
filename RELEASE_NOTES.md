# v0.0.5 — Recent history

**Preview for Omarchy / Arch x86_64.** This build adds a familiar Summary and a small per-user collector so the graphs can show the last minute when Task Manager is opened again.

- **Summary:** compact CPU and memory graphs, running applications and a direct route to Find an app. Existing users can keep their saved page.
- **History after Super + W:** the installed user service collects basic CPU, memory, disk and network readings once a second while the window is closed. Reopening imports its latest minute. It starts on the first normal launch and then with the user session.
- **Separate controls:** Pause live view freezes the displayed readings; Background monitoring in the menu disables and stops the independent collector. The choice persists. Detailed process, service, GPU and per-app polling runs only while the window is open.
- **Bounded local data:** history lives in a private runtime directory, is replaced atomically and expires. The collector requires fresh data before the app reports startup success. It has no network listener and does not enumerate processes.

## Install for testing

After this release is published, download the [x86_64 package](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.0.5/omarchy-task-manager-0.0.5-1-x86_64.pkg.tar.zst) and [SHA256SUMS](https://github.com/tcballard/omarchy-task-manager/releases/download/v0.0.5/SHA256SUMS) to the same directory, then run:

```bash
sha256sum --ignore-missing --check SHA256SUMS &&
sudo pacman -U ./omarchy-task-manager-0.0.5-1-x86_64.pkg.tar.zst
```

Open Task Manager from the launcher. To check the new behaviour, leave it open for ten seconds, close it with Super + W, wait ten more seconds and reopen. The graphs should include the time when the window was closed. The menu shows setup errors and lets you switch Background monitoring off. [Keyboard shortcut setup](https://github.com/tcballard/omarchy-task-manager/blob/v0.0.5/docs/GUIDE.md#keyboard-shortcut) remains optional.

On an Omarchy channel, `sudo pacman -Syu omarchy-task-manager` installs whichever version that channel publishes. This release does not update the upstream channel package. The existing v0.0.4 package remains available for rollback. Before a downgrade, use the menu to turn Background monitoring off or run `systemctl --user disable --now omarchy-task-manager-monitor.service`; v0.0.4 does not install this unit. Downgrade only with a verified v0.0.4 package. User preferences and application history remain; background graph cache is temporary.

## Verification boundary

CI builds and tests on Ubuntu and Arch, including collector and GUI history lifecycle, real user-service controls, package installation, upgrade and removal. The exact source and checksums are in `BUILD-INFO.txt` and `SHA256SUMS`. Live Super + W/reopen, login, toggle and desktop usability on the XPS still require acceptance. The earlier XPS screenshot predates these features. No ARM or new GPU hardware test is claimed. The End task simplification remains planned.

[Changes since v0.0.4](https://github.com/tcballard/omarchy-task-manager/compare/v0.0.4...v0.0.5)
