# QtSvg dependency validation

Task Manager identifies running applications by their icons. `ui/icons.h` uses
`QIcon(path)` for absolute paths and `QIcon::fromTheme(name)` for theme icons,
then renders a pixmap. Packaging includes `qt6-svg`. This makes QtSvg security
relevant; no crafted-icon exploit against Task Manager has been reproduced.

## Functional compatibility and this security requirement

The functional source-build minimum remains **Qt 6.4**. It is not a statement
that an unpatched Qt 6.4 installation is security-supported. For
[CVE-2026-8168](https://www.qt.io/blog/security-advisory-cve-2026-8168), disclosed
19 October 2026, Qt lists affected versions **4.1.0–6.8.8** and
**6.9.0–6.11.1** (status before 4.1.0 unknown). Excessively nested SVGs can
exhaust the stack during parsing/rendering/tree cleanup.

| Installed QtSvg | Requirement for this CVE |
| --- | --- |
| Final 6.8.9+ within 6.8 | Upstream fix included |
| Final 6.11.2+ within 6.11 | Upstream fix included |
| Final 6.12.0+ in Qt 6 | Upstream fix included |
| 6.4–6.8.8, all 6.9/6.10, 6.11.0/6.11.1 | Vendor package with the **complete**, appropriate branch fix set, reviewed against the exact package version/release |
| Prerelease, custom or unidentified build | Unverified until its actual fix provenance is reviewed |

An older source build is supported with respect to this CVE only with that
vendor evidence and passing icon rendering/runtime validation. No older target
installation has been validated here. This table concerns one CVE, not all Qt
security advisories or an upstream maintenance/support commitment. The archived
v0.1.2 binary additionally imports Qt 6.12 symbols: patched 6.8/6.11 does not make
that binary ABI-compatible. Rebuilding from source and binary compatibility are
separate questions.

The advisory requires **all** listed fixes for a branch. It links ten changes
each for 6.8 and 6.11, including follow-up correctness/performance changes and
tests. A package release number, isolated patch, CVE mention or base Qt version
alone is insufficient. Use the complete bundles linked by Qt:
[6.8](https://download.qt.io/archive/qt/6.8/CVE-2026-8168-qtsvg-6.8.zip) and
[6.11](https://download.qt.io/official_releases/qt/6.11/CVE-2026-8168-qtsvg-6.11.zip).
For another branch require a vendor-maintained equivalent of the complete fix
set; these bundles are not instructions to apply mismatched patches yourself.

## Collect evidence on each actual runtime target

Run as your ordinary user from the reviewed checkout, after building the test
target against that environment's Qt (CMake config also needs the documented
development dependencies):

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --target icon-test
set -o pipefail
QT_QPA_PLATFORM=offscreen ./scripts/check-qtsvg.sh --icon-probe ./build/icon-test | tee QTSVG-VALIDATION.txt
```

Keep the checkout commit, command exit status, report and snapshot/channel
record together. The report includes UTC time, architecture, probe hash, runtime
Qt version, `pacman -Q/-Qi` package identity (epoch/version/pkgrel), packager and
build metadata, `pacman -Qkk` file metadata checks, and hashes/owners of the
QtSvg library and plugins actually mapped by the probe via `/proc/self/maps`.
It rejects missing/unowned/modified package files and missing rendering evidence.
The file hashes are evidence for later comparison, not a package-signature
verification or proof against a compromised package database.

Exit **0** means the observed runtime files belong to a fixed upstream package
or an explicitly reviewed vendor backport. Exit **1** means an affected upstream
version without backport evidence. Exit **2** means unverified (missing package,
failed render, unknown version/provenance or incomplete evidence). Non-pacman
systems require equivalent vendor package and loaded-library evidence; a
successful Ubuntu rendering test alone is not a security pass.

The probe runs the production `Icons` provider on benign, temporary external and
theme SVGs at 16/32/64 pixels and checks expected colours, so fallback icons do
not pass. It cleans up its temporary theme. It does not load adversarial SVGs,
change the user's theme or install anything. Headless results validate these
paths only. On the desktop also observe normal application icons in Summary and
Applications and switch real themes/scales; retain this as a separate result.
Use the same user/session Qt environment as Task Manager; record any
`QT_PLUGIN_PATH`, `LD_LIBRARY_PATH` or other loader overrides. A helper's result
does not establish the libraries in an already-running app: restart Task Manager
after any normal system update and validate that installation/session.

### Vendor-backport exception

A reviewer must check a vendor advisory/immutable recipe or source revision for
the exact package release, map **all** applicable Qt fixes (including follow-ups)
to that source and retain the reviewed evidence. The tool cannot verify those
claims automatically. Supply an attestation containing these exact lines,
replacing the example identity, evidence URL and reviewer:

```text
package=qt6-svg 6.8.8-5
cve=CVE-2026-8168
complete-branch-fix-set=yes
vendor-evidence=https://vendor.example/immutable-recipe-or-advisory
reviewed-by=Reviewer name and review reference
```

```bash
QT_QPA_PLATFORM=offscreen ./scripts/check-qtsvg.sh --icon-probe ./build/icon-test --backport-evidence reviewed-backport.txt
```

The report retains the attestation and hash, labels it **operator-reviewed**, and
requires an exact package/version/release match. No vendor exceptions are
preapproved in this repository; the example is not actual backport evidence.

## Arch and Omarchy evidence checked on 20 October 2026

[Arch Extra](https://archlinux.org/packages/extra/x86_64/qt6-svg/) lists
`qt6-svg 6.12.0-1` for x86_64, depending on `qt6-base`; that version includes
the upstream fix without a backport. This is repository availability, not an
installed-runtime observation. Omacom's
[recipe](https://github.com/omacom/omarchy-pkgs/blob/42be3b038eddd14281ac14c1f102c9daeda1405f/pkgbuilds/omarchy-task-manager/PKGBUILD)
at `42be3b038eddd14281ac14c1f102c9daeda1405f` depends on unversioned `qt6-svg`.
Its metadata uses normal promotion, with no fast-ring override. Consequently each
Edge/RC/Stable snapshot and installation needs its own evidence; the latest Arch
listing and an Omarchy version string cannot certify it.

Keep system Qt under the distribution's package/update policy. Do not bundle,
replace or partially upgrade Qt libraries to satisfy this check. A failed older
snapshot requires a compatible vendor-fixed snapshot/package, or remains
unsupported for this CVE. No application release is needed solely to distribute
a fix already provided by upstream Qt. This work does not change the installer,
functional CMake minimum or channel policy.
