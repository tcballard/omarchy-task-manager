# Credits and licences

Application code and included SVG icon: Tom Ballard, MIT. Icon is original vector artwork.

Qt 6 is dynamically linked and supplied by the operating system under its applicable LGPL/GPL/commercial terms; no Qt runtime is bundled. Rust dependencies are locked in Cargo.lock: serde/serde_json (MIT OR Apache-2.0), libc (MIT OR Apache-2.0), and their transitive dependencies retain their own notices. Review full dependency licence output before a public binary release.

btop is a product reference. No btop code or assets are included. Resources was reviewed for comparison only; no Resources code is included.

The community Built for Omarchy App badge is referenced remotely from tcballard/omarchy-badges at a fixed commit. It is not official approval or a compatibility certification.

## Locked Rust dependency licence declarations

- itoa 1.0.18: MIT OR Apache-2.0
- libc 0.2.189: MIT OR Apache-2.0
- memchr 2.8.3: Unlicense OR MIT
- proc-macro2 1.0.107: MIT OR Apache-2.0
- quote 1.0.47: MIT OR Apache-2.0
- serde 1.0.229: MIT OR Apache-2.0
- serde_core 1.0.229: MIT OR Apache-2.0
- serde_derive 1.0.229: MIT OR Apache-2.0
- serde_json 1.0.151: MIT OR Apache-2.0
- syn 3.0.6: MIT OR Apache-2.0
- unicode-ident 1.0.26: (MIT OR Apache-2.0) AND Unicode-3.0
- zmij 1.0.23: MIT

## Primary implementation references (checked 20 September 2026)

- [Quattro typography and style](https://github.com/omacom/omarchy/blob/quattro/shell/Commons/Style.qml), blob `ec61252b7626fead302a2b69012e548b06982e88`: monospace fontconfig alias and font scale.
- [Shell theme template](https://github.com/omacom/omarchy/blob/quattro/default/themed/shell.toml.tpl), blob `b0a68d8b0c44ca0b146c727beb72d27f8a27b5d4`: popup colors, type and control tokens.
- [Omarchy current font](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-font-current), blob `839bd4db7b629db34c30988992fe0da0b12925a7`.
- [Quattro keyboard panel](https://github.com/omacom/omarchy/blob/quattro/shell/Ui/KeyboardPanel.qml), blob `b2fb218f46b40dd7f907fc123e714d09319ed2f8`: consulted for lifecycle conventions; our standalone Qt window is not that layer-shell component.
- [Kernel DRM usage-stat specification](https://docs.kernel.org/gpu/drm-usage-stats.html): client deduplication, engine capacity and byte units.
- [XDG autostart specification](https://specifications.freedesktop.org/autostart/latest/): per-user precedence and Hidden semantics.

These are references for original implementation, not bundled source or claims of upstream endorsement. External system programs retain their own licenses and are not bundled.
