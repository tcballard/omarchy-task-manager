# v0.1.2 — Understand sustained CPU and memory use

**Prepared for release; not yet published.**

When your computer feels slow, Summary now explains sustained high CPU or memory
readings and gives you a route to inspect running applications. A brief spike
won't trigger the guidance. Missing, paused or stale samples won't be presented
as a diagnosis, and Task Manager never picks an application to close for you.

The guidance uses at least ten seconds of valid readings at 90% or higher. It is
an indication of sustained use, not proof of a bottleneck. The existing normal
close and confirmed force-quit workflow remains available in Applications.

This release also corrects our package metadata and release process. Task Manager
is a source-built Qt app, so new packages follow **Edge → RC → Stable** alongside
compatible libraries. Build artifacts now carry Qt/library versions and full
package build information. Publishing requires an explicit workflow action.

## Availability and installation

| Distribution | v0.1.2 status |
| --- | --- |
| GitHub release | Pending publication |
| Omarchy Edge | 0.1.2-1 publication not yet verified |
| Omarchy RC | 0.1.2-1 publication not yet verified |
| Omarchy Stable | 0.1.2-1 publication not yet verified |

Update this table from the [release checklist](docs/RELEASE_CHECKLIST.md) at
publication and promotion time. A GitHub release or merged package PR does not
establish channel availability. Normal installation uses your selected channel:

```bash
sudo pacman -Syu omarchy-task-manager
```

That command installs the version your channel currently serves, which may still
be v0.1.1. Do not manually install an Edge/rolling-Arch binary onto an older Qt
snapshot solely because the source release exists.

## Verification and rollback

See [the v0.1.2 record](docs/VERIFICATION-0.1.2.md) for current checks and remaining
gates. Historical XPS acceptance of v0.1.0 is not acceptance of this build. Live
Summary layout, v0.1.1 sampling changes and target-channel package validation
remain pending. No new screenshot is claimed.

No preference/history schema changes are included. Before removal or downgrade,
turn off Background monitoring; retain preferences and history. Follow the
[removal guidance](docs/GUIDE.md#removal) and use a package compatible with the
installed channel's libraries.
