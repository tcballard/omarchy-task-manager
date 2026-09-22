# Omarchy packaging for v0.0.4

Task Manager was published to Edge as `0.0.3-3` through [omarchy-pkgs PR #579](https://github.com/omacom/omarchy-pkgs/pull/579). The maintainer requested v0.0.4 followed by promotion beyond Edge on 22 September 2026.

## Promotion contract

Reviewed `omacom/omarchy-pkgs` at `77212489259697324f331eeefe735848fdc552f9`, including its README, `helpers/package-metadata.sh`, `bin/build-matrix`, and build/publish workflows.

- Release `0.0.4-1` under the existing `omarchy-task-manager` package name, for x86_64.
- Include the pause/resume and worker-shutdown fixes from app PRs #11 and #12 directly. Remove their downstream patches when updating the upstream recipe.
- Remove `channels: ["edge"]` and set `release_ring: "fast"`. Current `bin/build-matrix` then selects `edge rc stable`; the current CI publishing workflow publishes one tested artifact to all eligible channels. The README's separate-per-channel-build description refers to the host path and does not describe this CI path.
- Retain the declarative GitHub watch and `allow_prerelease: true`. v0.0.x remains a preview even when available on Stable.
- Build from the published versioned source archive, pinned by SHA-256. The template is `packaging/PKGBUILD`; its placeholder must be replaced by `scripts/package-source.sh`.
- Keep package ownership under `/usr`, optional gdb/NVIDIA dependencies, user preferences/history and personal bindings unchanged. No install hook, root helper or service is added.

## Release first, then package PR

1. Merge the v0.0.4 release PR after CI passes. The existing release workflow publishes the tested assets only after both Ubuntu and Arch jobs succeed on main.
2. Verify the published source digest and generated repository archive against that release. Do not regenerate different bytes for a published version.
3. Update the contributor fork's recipe to `0.0.4-1`, remove both backport patches, and apply the fast-ring metadata. Submit a separate PR to `omacom/omarchy-pkgs`.
4. Run the upstream metadata validator and build-matrix helper. The expected matrix is one x86_64 entry targeting `edge rc stable`.
5. Let the upstream PR build validate the released source download and package. Maintainer merge and the publishing workflow control actual channel availability.

For an unsigned local build on a machine with the documented builder prerequisites:

```bash
bin/repo build --local --package omarchy-task-manager --arch x86_64 --mirror edge --dry-run
bin/repo build --local --package omarchy-task-manager --arch x86_64 --mirror edge
```

Do not run repository signing or production commands as contributor validation.

## Evidence boundaries

Run `python3 tests/release_metadata.py` and `python3 tests/packaging.py` to check aligned versions and reproducible source/recipe archives. These checks do not build the application. The release CI builds and tests on Ubuntu and Arch, including package installation, upgrade from v0.0.2, reinstall, offscreen launch and removal with state preservation.

The existing Edge package's successful upstream build and prior XPS use are historical evidence. This release makes no new live Wayland, GPU or ARM acceptance claim. ARM is not declared in the recipe. CI and upstream publication results must be recorded against their own commit/run, separately from historical `VERIFICATION.md` and `HARDENING.md` records.

Until upstream publication succeeds, README installation remains explicit about Edge availability. RC and Stable availability must not be announced merely because the app release exists.
