# v0.1.2 preparation evidence

Date: 14 October 2026. Base: `49a861ab7bfbeb3f4198ea31e00b0714cf4529e1`.
Environment: Ubuntu 24.04 x86_64; no Rust/CMake/Qt toolchain or live Omarchy desktop.
The release-preparation PR identifies the resulting source commit; CI artifacts
identify their exact commit and run separately. No binaries were built locally.

## Reproduced during preparation

- `python3 tests/release_metadata.py`: exit 0, all version labels aligned at 0.1.2.
- `python3 tests/packaging.py`: exit 0, two identical source/recipe generations,
  matching source checksum and normal-promotion metadata. No fast-ring field.
- `{ tail -n +2 ui/LoadSummary.js; cat tests/load_summary.js; } | node`: exit 0,
  existing sustained-load, spike, missing-data, interval, pause and stale checks.
- `bash -n scripts/check-channels.sh`: exit 0.
- `git diff --check`: exit 0.
- `./scripts/check-channels.sh 0.1.2-1`: exit 1 as expected; all channels contain
  the older version. Read at 2026-10-14 09:50 UTC, architecture x86_64:

| Channel | Version | Database SHA-256 |
| --- | --- | --- |
| Edge | 0.1.1-1 | 74255c131971743db1722d123522ab86ac6171c58c99f4502f49fc2731d6ea44 |
| RC | 0.1.1-1 | 8936abc1f71664f86468c43207720cf83e5fc4eb4b9ebf730c5104f504fdb4f9 |
| Stable | 0.1.1-1 | 49ec12cf4cd2b72f4be7971f9c9a56e5c34dcca444202ca080576785ada5b3dd |

Database URLs: `https://pkgs.omarchy.org/<channel>/x86_64/omarchy.db`, with
cache-busting query values 1791971401 (Edge), 1791971407 (RC), 1791971412 (Stable).
This is publication evidence only; it does not certify Qt compatibility.

## Pending release gates

- Fresh Ubuntu and Arch CI on the PR's exact head: inspect GitHub Actions.
- Actual Omarchy Edge snapshot build, installed Qt versions, package lifecycle
  and live desktop acceptance; then RC/Stable promotion evidence. No target
  snapshot or target Qt version has been tested in this environment.
- v0.1.2 Summary guidance layout/workflow and outstanding v0.1.1 sampling changes
  on the XPS. No new screenshot: no live desktop or local Qt renderer available.
- Publication decision, release tag, binary assets and checksums. The reproducible
  source/recipe test does not certify a binary or publish a release.

Historical evidence remains in `VERIFICATION.md` and `HARDENING.md`; it is not
rerun evidence for v0.1.2. See [the checklist](RELEASE_CHECKLIST.md) for exact
build/snapshot identity fields and the announcement gate.
