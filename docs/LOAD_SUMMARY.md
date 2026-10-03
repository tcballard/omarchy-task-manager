# Summary guidance (unreleased)

The Summary screen helps a user decide where to look when their computer feels
slow. It keeps the existing Applications route and safe close/force-quit workflow.

The explanation uses the existing CPU and memory history. Every valid sample
must show at least 90% use for a span of at least ten seconds to describe sustained
high use. This is a conservative presentation heuristic, not a measurement of
kernel pressure or proof of a bottleneck. Memory uses the existing used/total
metric; no per-app cause is inferred. A brief spike does not trigger guidance.

Missing or invalid readings, insufficient history, gaps beyond twice the selected
sample interval (minimum three seconds), pauses and stale responses prevent an
unsupported conclusion. Resume waits for a new sample. Discontinuities already
clear history in the bridge. An available CPU or memory signal can still be
described when the other is unknown. Low readings do not rule out other causes.

Acceptance: open Summary during sustained CPU use or low available memory, follow
Find an app, and inspect current readings without being told to terminate a named
application. Repeat after a short spike, pause/resume, a sampling interruption,
and at small panel sizes and large fonts. No automatic process action is added.

Verification: tests/load_summary.js exercises sustained/brief readings, missing
data, gaps, sample intervals, pause and stale states. It runs in the Qt UI test
through QJSEngine; it can also run with Node by concatenating LoadSummary.js
(without its .pragma line) and the test. Live Omarchy layout and workflow
acceptance remain required; portable tests do not establish those.
