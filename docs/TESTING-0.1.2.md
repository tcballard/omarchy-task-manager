# Test v0.1.2 on the XPS

This installs an **unpublished, unsigned development package** from the existing
successful CI run. It is not a GitHub release or an Edge, RC or Stable package.
Your current XPS environment has not been inspected remotely. The command below
checks it locally and refuses installation when a prerequisite fails.

## One command

Close Task Manager, then paste this into a terminal as your normal Omarchy desktop
user. It downloads the installer completely before running it, preserves failure
status, and uses an immutable source commit:

```bash
bash -c 'f=$(mktemp) || exit; curl -fsSL --connect-timeout 15 --max-time 120 https://raw.githubusercontent.com/tcballard/omarchy-task-manager/182e5b3a2bee7bb8755edbd9a260f03668e20080/scripts/test-install-v012.sh -o "$f" && bash "$f"; s=$?; rm -f -- "$f"; exit "$s"'
```

Only the package transaction uses `sudo`. Pacman asks for confirmation and retains
its configured signature policy. If local policy requires signatures for local
packages, this unsigned test package is refused; do not weaken that policy.

The command requires native `curl`, `github-cli` (`gh`), `jq`, `libarchive`
(`bsdtar`), `pacman`, `systemd`, `glibc` (`ldd`), `coreutils`, `util-linux`
(`flock`) and `procps-ng` (`pgrep`). GitHub requires authenticated artifact access:
if needed, complete `gh auth login` once and rerun the same command. Missing tools
are reported without automatically changing your system.

## What is checked

1. x86_64 Omarchy, the successful run, artifact identity, expiry and source head.
2. The pinned SHA-256 of the complete ZIP, every entry in `SHA256SUMS`, the binary
   package hash, recorded merge/run identity, package name/version/architecture,
   and agreement between the package's `.BUILDINFO` and the CI report.
3. Every declared dependency is already installed. All four Qt packages must be
   in the **6.12 family**. This binary imports `Qt_6.12`; unversioned dependency
   names alone do not establish compatibility. Other Qt families are deliberately
   refused even if a later version might work.
4. Both binaries resolve their libraries and symbols with `ldd -r`. The staged
   application must pass a 20-second offscreen smoke test with isolated home,
   preferences, state, cache and runtime directories.
5. For an upgrade, the exact previous package is saved from pacman's configured
   cache. If missing, a download-only request uses the existing repository
   database; the downloaded version must equal the installed version. If it
   cannot be saved, installation stops. No database refresh, library upgrade,
   channel switch, signature override or public release occurs.
6. The user monitor is stopped if active, the package is installed with
   `pacman -U`, package files are checked, and the installed app passes another
   isolated smoke test. The monitor's previous running state is restored.

An incompatible machine is an expected safe stop. **Do not install Qt alone or
force the package.** Keep the current Omarchy channel and share the recorded
runtime versions and failure log so a build against that snapshot can be prepared.
A local preflight pass is still not live Wayland/Hyprland acceptance or proof of
compatibility with an entire channel.

To collect evidence without installing, use the same command with
`bash "$f" --check` in place of `bash "$f"`.

## Revert

Before installation the command prints an exact `bash /…/revert.sh` command. Keep
it and the workspace. Close Task Manager and run that command to restore the saved
previous package. A fresh test installation is reverted by removing only Task
Manager. Preferences and history remain. No dependency removal or system downgrade
is performed. The original monitor running state is restored; its enablement is
not changed by installation or rollback.

The rollback script verifies its saved package checksum and refuses to overwrite
a later installed Task Manager version. Installation failures after the transaction
begins attempt rollback automatically; if pacman or service recovery fails, the
log prints the command to retry. A power failure or terminated shell may require
running that saved command manually. Keep the workspace until testing is done.

Logs, repository configuration, Qt versions, artifact metadata, assets and the
previous package stay under
`${XDG_STATE_HOME:-~/.local/state}/omarchy-task-manager/test-builds/38545446855.*`.
Review logs and repository URLs before sharing them; nothing is uploaded.

## Live acceptance still needed

Open Task Manager from the launcher and follow
[the live XPS checklist](GUIDE.md#live-xps-acceptance). Record:

- Omarchy version/channel, Qt versions and the workspace's package identity.
- Summary guidance under sustained CPU/memory load and pause/resume behaviour.
- Summary → Applications, searching, layout/scale and theme behaviour.
- Normal close of a disposable unsaved document, save-prompt cancellation and
  force-quit confirmation cancellation.
- Background history after closing/reopening, GPU readings and the outstanding
  v0.1.1 sampling checks.
- Revert, reopen the previous version, and confirm preferences/history remain.

Report failures and checks not run. Live acceptance is pending until these are
observed on the XPS; publication and channel promotion remain separate decisions.

## Inspected artifact: 18 October 2026

| Item | Verified value |
| --- | --- |
| Run | [38545446855](https://github.com/tcballard/omarchy-task-manager/actions/runs/38545446855) |
| Artifact | `arch-development-package`, ID `11884681461` |
| Source branch head | `384322478a2e7155f138edd897c7b418469c64d4` |
| Build commit | `29f50d058e63e1a1200362c536c0c7f7739f0048` |
| Source tree | `718aa3cdbb4f78feaabe948e671df58834928eac` |
| Package | `omarchy-task-manager-0.1.2-1-x86_64.pkg.tar.zst` |
| Build Qt | base `6.12.0-2`; declarative/wayland/svg `6.12.0-1` |
| Build target | Rolling Arch CI, not an Omarchy snapshot |
| Artifact expiry | 12 January 2027, 09:51:43 UTC, unless deleted earlier |

The build commit is GitHub's signed PR test merge: parents are base
`49a861ab7bfbeb3f4198ea31e00b0714cf4529e1` and the source branch head above.
Its tree equals that branch head's tree. All **71 source archive files** match
their Git blob hashes in the merge tree. The installer remains tied to these old
tested bytes even when PR #26 gains documentation or installer changes.

```text
ZIP SHA-256:
aa38e44841dca2586c3e33e77df37787837e51311da64ad99e36413e3a068cf8
Binary package SHA-256:
724396a9d950fceeda6c1dfe79f93201f9db8e192942124e968b67c86a74b87b
Source archive SHA-256:
bcf55c298fb7f4f1860522a2a29d5d971b2517fe0a5b4bc0a3e33e0705d53d8e
```

The downloaded ZIP matches GitHub's artifact digest. All nine internal checksums
passed. Actual `.PKGINFO`, `.BUILDINFO`, file paths, owner/mode entries and ELF
architecture/symbol requirements were inspected. The package contains the GUI,
Rust core, user service, desktop entry, icon, licence and example bindings under
`usr/`; no installation hook, bundled user data or world-writable entry was found.
Namcap reported warnings but no errors; optional/runtime Qt plugin dependencies
remain intentional. The original Ubuntu and Arch jobs succeeded, including
installation, upgrade and removal; the release job was skipped.

Installer fixtures exercise corruption, expiry, wrong source, incompatible Qt,
missing dependencies/symbols, staged/installed smoke failures, an open app, missing
rollback package, failed transactions, fresh installation, upgrade, rollback,
tampered rollback bytes, later-version protection and check-only mode. These are
isolated command mocks, not a package build or live desktop validation.
