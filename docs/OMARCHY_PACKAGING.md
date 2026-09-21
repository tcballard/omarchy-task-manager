# Omarchy packaging for v0.0.3

The goal is a normal repository install and updates through Omarchy's package
system. This is packaging preparation, **not an accepted or published Omarchy
package**. v0.0.3 publishes the source and contribution artifacts for upstream review.

## Package contract

Reviewed `omacom/omarchy-pkgs` at
[`b3e781868f763112866ae7ac03ac0c4028434ced`](https://github.com/omacom/omarchy-pkgs/tree/b3e781868f763112866ae7ac03ac0c4028434ced)
on 21 September 2026, including its README, `docs/upstream-sources.md`,
`helpers/upstream-watch.py` and `bin/repo` / `bin/build`.
No recipe for this app existed in that snapshot. AUR availability was not verified;
this contribution uses our own source recipe rather than an AUR import.

- Keep the existing package name, `omarchy-task-manager`, so a repository build
  upgrades an installation made from our GitHub package without a rename or conflict.
- Build the Rust worker and Qt application from the versioned source release,
  pinned by SHA-256. The recipe template is `packaging/PKGBUILD`; generate it before
  use so `SOURCE_DIGEST` is replaced. Local and repository builds use the same recipe.
- Target x86_64 only. ARM support is not claimed or tested.
- Propose `channels: ["edge"]` while the app is a preview. Do not force stable/rc
  publication, a fast release ring, or a quarantine override.
- The declarative GitHub watch explicitly accepts prereleases because v0.0.n
  releases are marked as previews. Drafts and nonmatching tags are excluded by the
  official watcher. It updates versions and source hashes, not our build functions.
  Reconsider preview selection and channel policy with maintainers for v0.1.0.
- The package owns only its binaries, desktop entry, icon, licence and shortcut
  example under `/usr`. It installs no root helper, startup service or user-config
  hook. Dependencies are installed by pacman; gdb and NVIDIA telemetry remain optional.
- Installation does not activate the shortcut. User preferences, history and
  personal bindings are preserved through upgrades and removal.

## Generate and validate

From the app checkout:

```bash
python3 tests/release_metadata.py
python3 tests/packaging.py
cd dist
makepkg -si
```

Run makepkg as a normal user on Arch/Omarchy. The source archive beside the
generated recipe is also makepkg's local cache of the release download; it is
verified against the same digest. Before publication, its remote URL is not
available. Never submit a development archive as an already released source.

`scripts/package-source.sh` produces the source archive, resolved `PKGBUILD`, and
`omarchy-task-manager-VERSION-omarchy-pkgs.tar.gz`. That last archive contains only:

```text
pkgbuilds/omarchy-task-manager/PKGBUILD
pkgbuilds/omarchy-task-manager/.omarchy/package.json
```

CI builds this exact recipe in an Arch container, checks package contents and
dependencies with namcap, and tests a fresh install, an upgrade from the released
v0.0.2 package, reinstall, normal-user offscreen launch, and removal. It checks that
existing preferences and history survive. These are CI gates, not a claim about
results before a run completes. Source/handoff reproducibility is checked separately.

## Release and upstream handoff

1. Publish the reviewed v0.0.3 version/release PR with `pkgrel=1` and its tested
   assets. Keep
   `prerelease: true`. Include the generated repository archive in `SHA256SUMS`.
2. Download the source, repository archive and checksums from that actual release;
   verify them. Do not regenerate a different source archive for the same tag.
3. In a fresh contributor checkout of `omacom/omarchy-pkgs`, read current instructions
   again. Extract the reviewed repository archive there and inspect the two-file diff.
4. With no source tarball preseeded, run the official unsigned build on a machine
   with its supported container engine:

   ```bash
   bin/repo build --local --package omarchy-task-manager --arch x86_64 --mirror edge --dry-run
   bin/repo build --local --package omarchy-task-manager --arch x86_64 --mirror edge
   ```

   `--local` prevents forwarding to a configured repository host. Do not run release,
   deploy, sign, promote or sync as contributor validation. The dry run also requires
   the builder prerequisites; it is not a substitute for building.
5. Submit the package PR with the release URL, source digest, exact tested commit,
   architecture, build output and live Omarchy install/launch evidence. Upstream
   submission and acceptance are separate from merging this app-side preparation.
6. Only after acceptance **and publication on the user's configured channel**,
   document `sudo pacman -Syu omarchy-task-manager` as the normal install. Existing
   users then receive published newer versions through normal system updates.

The full official builder, downloading the new release from an empty source cache,
and live Wayland/launcher acceptance remain release/submission checks. The development
environment used for this change is Ubuntu without Docker/Podman or makepkg; package
execution is delegated to Arch CI. No production repository has been modified.

Local preparation checks passed on 21 September 2026: release metadata alignment,
two identical archive generations, source checksum/version/layout checks, shell
syntax for the recipe, generator and workflow run blocks, and `git diff --check`.
The official watch helper at the pinned revision accepted our metadata and, with
an offline release feed, selected a published preview while excluding a draft and
a nonmatching tag. These checks validate the handoff, not the official package build.
The PR's Arch run is the evidence for package execution. The first package lint run
caught a missing `hicolor-icon-theme` dependency; the recipe now declares it. Other
namcap warnings include dynamically loaded Qt plugins and subprocess dependencies
that static linking analysis cannot establish; these dependencies are retained.
The preparation PR tested a package revision upgrade from 0.0.2-1 to 0.0.2-2.
The v0.0.3 release CI gates publication on the app version upgrade from 0.0.2-1
to 0.0.3-1 with the same preservation checks.
