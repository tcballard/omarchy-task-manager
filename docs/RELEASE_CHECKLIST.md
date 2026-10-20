# Release and channel checklist

A GitHub release, an Edge package, and RC/Stable promotion are separate events.
Task Manager is built against Qt: keep Omacom's normal **Edge → RC → Stable**
promotion with its library snapshot. Never restore `release_ring: "fast"`.

For the existing unpublished CI package, use the [v0.1.2 test installer](TESTING-0.1.2.md)
and its rollback. Its local preflight is separate from the snapshot and live
acceptance gates below.

Policy source: [omarchy-pkgs #904](https://github.com/omacom/omarchy-pkgs/pull/904)
and [package policy](https://github.com/omacom/omarchy-pkgs#what-can-be-on-the-fast-ring).

## Prepare the source release

- [ ] Align Cargo, lockfile, CMake, app labels and PKGBUILD versions; reset pkgrel
      for a new upstream version. Run `python3 tests/release_metadata.py` and
      `python3 tests/packaging.py`.
- [ ] Review all changes since the previous release, including already merged
      features. Update release notes and retain historical evidence separately.
- [ ] Require green Ubuntu and Arch CI for the exact source commit. Download
      `arch-development-package`; check `SHA256SUMS` and the commit in
      `BUILD-INFO.txt`. Keep the source archive, recipe, binary, package file list,
      namcap report and `PACKAGE-BUILDINFO.txt` together.
- [ ] Record the build environment. CI records the Qt packages and full package
      `.BUILDINFO`, but uses rolling Arch, **not** an Omarchy channel snapshot.
      Its success does not prove Edge, RC or Stable compatibility.
- [ ] Retain checksummed `QTSVG-VALIDATION.txt` from Arch CI. Require its
      security result and ordinary absolute/theme SVG pixel checks to pass;
      review any vendor-backport attestation and complete fix-set source. Run
      `bash tests/qtsvg-security.sh` for the evidence-policy regression checks.
      This is CI runtime evidence, not target/XPS evidence.
- [ ] Complete live acceptance for changed behaviour (v0.1.2: Summary guidance,
      pause/resume and layout, plus outstanding v0.1.1 sampling checks). Record
      `omarchy-version`, architecture, Qt versions and source/package identity.
- [ ] Confirm the publication decision. On main, manually run **Build and test**
      with `publish_release=true` only after these gates are satisfied. Ordinary
      pushes and default manual runs build artifacts without publishing. The
      release job waits for both test jobs and refuses to rewrite an existing
      release. Verify the new tag, assets and checksums afterwards.

## Validate the Omarchy package and snapshot

- [ ] Use Omacom's current build tooling at a recorded upstream commit to build
      the exact recipe against Edge. Keep default channel metadata; no fast ring
      or channels override. Record upstream build run, recipe tree/hash, source
      commit/digest, package version (including pkgrel), architecture and checksum.
- [ ] Capture the configured repository URLs and resolved Arch snapshot date from
      the builder, its Qt/base-library package versions, and package `.BUILDINFO`.
      In the target environment record:

      ```bash
      omarchy-version
      pacman -Q omarchy-task-manager qt6-base qt6-declarative qt6-wayland qt6-svg glibc gcc-libs
      pacman-conf
      ```

      These commands describe an environment; attach build/install/test results
      as well. Record Qt versions from both build and installed target.
- [ ] On **each installed target snapshot**, run the [QtSvg security check](QTSVG_SECURITY.md)
      with that target's built `icon-test`. Retain package epoch/version/pkgrel,
      runtime file ownership/hashes, upstream-fixed or reviewed complete vendor
      backport status, report and exit status. Confirm ordinary external/theme
      SVGs also appear correctly in the live app. Record absent physical XPS or
      older-runtime evidence as **unverified**, never infer it from build Qt.
- [ ] Install and launch on that snapshot; exercise Summary → Applications,
      normal close/save prompt and force-quit cancellation with disposable apps.
      Check background monitoring, upgrade, removal and preference preservation.
      Follow [the guide](GUIDE.md#live-xps-acceptance). Record failures and not-run
      checks explicitly. A rolling Arch artifact is not a substitute.
- [ ] Let Omacom publish to Edge, then promote to RC and Stable with the compatible
      libraries. Record each promotion's snapshot and validation evidence; do not
      force an Edge binary into an older channel. Upstream operators own signing
      and promotion. A submitted or merged PR alone is not publication evidence.

## Check publication before every announcement

Run from the checkout, retaining stdout and exit status in the release record:

```bash
./scripts/check-channels.sh 0.1.2-1
```

This reads each live x86_64 database with a cache-busting URL and records time,
version and database digest. Exit 0 means all three contain the requested version;
exit 1 means at least one differs, is absent or could not be verified. A network
failure is **unverified**, not absence. This checks availability, not runtime
compatibility. Recheck immediately before announcing and after each promotion.

Use a dated table with separate rows for GitHub, Edge, RC and Stable. Say “GitHub
release published; Edge package pending” or “Edge: 0.1.2-1 verified; RC/Stable:
0.1.1-1, awaiting promotion” only when those are the actual results. Say “available
across the board” only after all three databases verify the intended version.

## v0.1.2 preparation record

| Stage | Status |
| --- | --- |
| GitHub v0.1.2 | Prepared in a PR; not published by this work |
| Edge 0.1.2-1 | Not yet verified as published |
| RC 0.1.2-1 | Not yet verified as published |
| Stable 0.1.2-1 | Not yet verified as published |
| Target snapshot build / live acceptance | Pending; no Omarchy desktop in preparation environment |
| QtSvg security / normal SVGs on target XPS | Unverified; no physical XPS access (issue #27) |

See [v0.1.2 verification](VERIFICATION-0.1.2.md) for dated evidence. Source release
preparation does not imply package submission, signing or promotion.
