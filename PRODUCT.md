# Product direction

Agreed 20 September 2026; Summary-first direction added 22 September 2026. This is the desired experience and the basis for product decisions, not a claim that every part is already implemented or verified. FEATURES.md records current capability; verification records describe tested behaviour. This direction supersedes the original SCOPE.md wherever product priorities differ.

## Who we build for

Joe Bloggs has a frozen spreadsheet and wants to close it and get back to work. He knows the application's name and icon, but should not need to understand PIDs, Linux signals, process trees or service managers.

Task Manager for Omarchy is an open-source, native, mouse-friendly way to find and deal with misbehaving applications. Familiarity, clarity and safe recovery take priority over diagnostic breadth and machine tuning. “Kill Excel” describes the familiar user need; it is not a claim that Microsoft Excel runs natively on Omarchy or that every Wine application can be identified reliably.

## Desired experience

- Ship Super + Alt + Delete as the default shortcut to open or focus Task Manager. The shortcut itself never terminates an app. Preserve existing user bindings and make any conflict visible. The launcher remains available for mouse users.
- Open to a familiar Summary on first launch with CPU/memory readings, recognisable running applications and an obvious Find an app route. Applications remains one click away with names, icons and search. Advanced information must not crowd the primary task. Existing users may retain their saved page.
- Make End task the obvious application action. Explain its effect in ordinary language. Attempt a normal window close where supported so the application can offer to save work; a request being sent does not mean the application has closed.
- If the application remains open, make Force quit easy to find. Name the affected application, warn that unsaved work may be lost, and require explicit confirmation. Never escalate automatically because a timer expires.
- Show whether the application closed, is still running, or could not be closed. Keep the panel responsive and provide a useful next step after an error.
- Keep Processes, Services and deeper performance views available as secondary tools. Simplifying the primary journey does not mean removing existing advanced capabilities.
- Use Omarchy's fonts, colours and floating-panel conventions. Mouse users can complete the entire journey; keyboard navigation remains supported.

The maintainer asked for a Windows-adjacent overview for a nontechnical, 50+ user on 22 September 2026. Summary is an entry point to the safe Applications workflow, not a diagnosis or an automatic recommendation to terminate a busy app.

## Boundaries

Feature parity with Windows Task Manager, btop or TMOG is not the measure of success. Do not expand the default interface into a tuning console just because a metric or control is available. Open source matters: users must be able to inspect, build, modify and contribute to the application.

Simplicity must not hide uncertainty or weaken action safety. Do not label an app unresponsive based only on high CPU or a sleeping process state. Do not invent app ownership, sensor readings or support. Revalidate process identity before acting, protect the desktop/session, and make ambiguity visible before ending a group. Closing a browser can affect multiple tabs; shared processes and multiple windows need an honest explanation.

## Acceptance scenarios

Use disposable applications and unsaved test documents. These are target acceptance checks; record results against a commit and environment before marking them passed.

| Scenario | Successful outcome |
| --- | --- |
| Shortcut | Super + Alt + Delete opens the panel or focuses its existing instance without closing any application. User bindings are not silently replaced. |
| First use | A person unfamiliar with Linux finds their spreadsheet by name/icon and locates End task without opening Processes, reading documentation or using a terminal. |
| Normal close | A responsive application with unsaved work can show its save prompt. Cancelling that prompt leaves the application running without a later automatic force quit. |
| Frozen app | After a normal close does not succeed, the user can explicitly confirm Force quit, understands the risk to unsaved work, and sees the result. |
| Cancellation | Cancelling the force-quit confirmation performs no destructive action. |
| Changing target | Refresh, sorting, app exit or PID reuse cannot redirect an action to another application. |
| Ambiguous or denied action | The panel explains the limitation; it does not guess at ownership, close unrelated apps or claim success. Technical detail is available when needed. |
| Slow computer | The user can identify high CPU or memory use in Applications without learning diagnostic terminology. |
| Native desktop | On a live Omarchy session, mouse and keyboard users can complete the flow at supported display scales and in light/dark themes. |

Watch a first-time user attempt the frozen-spreadsheet scenario without coaching. Record time to identify the app, wrong turns and whether the confirmation made sense. CI proves specific behaviour; it does not prove usability or live hardware compatibility.

## Priorities through v0.0.n

First audit the current Applications page and close/force-quit flow against these scenarios. Close usability and safety gaps before expanding diagnostics. The existing v0.0.1 labels include Close window and Force quit; the desired End task journey above still needs an implementation review and live acceptance.

Continue v0.0.n previews while iterating. v0.1.0 requires confidence in this everyday workflow as well as the documented packaging and live desktop acceptance. A longer feature checklist alone is not readiness.

Change this direction when the maintainer explicitly changes the product goal, and record the reason in the PR. Do not rewrite acceptance criteria merely to describe whatever has already been built.
