# Omarchy packaging for v0.1.1

Task Manager was published to Edge as `0.0.3-3` through [omarchy-pkgs PR #579](https://github.com/omacom/omarchy-pkgs/pull/579). The maintainer accepted v0.1.0 as the first non-preview release on 24 September 2026 and requested the v0.1.1 fixes followed by an update to the existing promotion PR #594.

**Publication result (25 September 2026):** [PR #594](https://github.com/omacom/omarchy-pkgs/pull/594) merged and the [publish run](https://github.com/omacom/omarchy-pkgs/actions/runs/36179238474) succeeded. [Omarchy confirmed](https://github.com/omacom/omarchy-pkgs/pull/594#issuecomment-5838328794) `omarchy-task-manager-0.1.1-1-x86_64` live in Edge, RC and Stable. The release process below records the completed promotion; v0.1.1's new GPU sampling and page transitions still need XPS acceptance.

## Promotion contract

Reviewed `omacom/omarchy-pkgs` at `77212489259697324f331eeefe735848fdc552f9`, including its README, `helpers/package-metadata.sh`, `bin/build-matrix`, and build/publish workflows.

- Release `0.1.1-1` under the existing `omarchy-task-manager` package name, for x86_64.
- Include the pause/resume and worker-shutdown fixes from app PRs #11 and #12 directly. Remove their downstream patches when updating the upstream recipe.
- Remove `channels: ["edge"]` and set `release_ring: "fast"`. Current `bin/build-matrix` then selects `edge rc stable`; the current CI publishing workflow publishes one tested artifact to all eligible channels. The README's separate-per-channel-build description refers to the host path and does not describe this CI path.
- Retain the declarative GitHub watch and `allow_prerelease: true`. The historical preview watch remains enabled; v0.1.1 itself is a regular release.
- Build from the published versioned source archive, pinned by SHA-256. The template is `packaging/PKGBUILD`; its placeholder must be replaced by `scripts/package-source.sh`.
- Keep package ownership under `/usr`, optional gdb/NVIDIA dependencies, user preferences/history and personal bindings unchanged. The package includes the existing systemd user monitoring service introduced in v0.0.5. First normal launch enables it; no install hook or root service is added.

## Completed release and package process

1. The v0.1.1 release PR merged after CI passed; the release workflow published the tested assets after its Ubuntu and Arch jobs succeeded.
2. The published source digest and repository recipe were compared with the versioned release; the [package PR](https://github.com/omacom/omarchy-pkgs/pull/594) records the matching hashes and build checks.
3. The package recipe moved to `0.1.1-1`, removed the downstream backport patches, and kept the fast-ring metadata.
4. Upstream metadata validation and the build matrix selected one x86_64 package for `edge rc stable`; the [publish run](https://github.com/omacom/omarchy-pkgs/actions/runs/36179238474) completed successfully.

For an unsigned local build on a machine with the documented builder prerequisites:

```bash
bin/repo build --local --package omarchy-task-manager --arch x86_64 --mirror edge --dry-run
bin/repo build --local --package omarchy-task-manager --arch x86_64 --mirror edge
```

Do not run repository signing or production commands as contributor validation.

## Evidence boundaries

Run `python3 tests/release_metadata.py` and `python3 tests/packaging.py` to check aligned versions and reproducible source/recipe archives. These checks do not build the application. The release CI builds and tests on Ubuntu and Arch, including package installation, upgrade from v0.0.2, reinstall, offscreen launch and removal with state preservation.

The existing Edge package's successful upstream build and prior XPS use are historical evidence. The maintainer accepted v0.0.5 on the XPS and confirmed logout/reboot startup and GPU checks on 24 September 2026. The new v0.1.1 GPU and snapshot changes still need an XPS pass. No other GPU hardware or ARM acceptance is claimed. ARM is not declared in the recipe. CI and upstream publication results must be recorded against their own commit/run, separately from historical `VERIFICATION.md` and `HARDENING.md` records.

Publication succeeded on 25 September 2026 in Edge, RC and Stable for x86_64. The README and release notes now use the repository package as their primary install path.
