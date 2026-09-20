# Project instructions

## Product alignment

Read PRODUCT.md before planning or changing this project. It defines the intended user, priorities and acceptance scenarios. The core task is: a person finds a frozen application and closes it without understanding Linux internals.

Prefer changes that make that journey clearer, safer or more reliable. Keep advanced diagnostics secondary. Do not add scope solely to match another task manager's feature list. Do not weaken identity checks, desktop protection, confirmation or honest reporting to simplify the UI.

Before implementing a feature, identify the user scenario it serves and how the result will be checked. If a proposed change conflicts with PRODUCT.md, surface the conflict; do not silently redefine the goal. Follow explicit maintainer direction and update the product brief when the goal changes.

## Context and evidence

- PRODUCT.md: desired experience and acceptance criteria.
- FEATURES.md and README.md: current capabilities, usage and limitations.
- ARCHITECTURE.md: implementation structure.
- SCOPE.md: historical build plan, not the current product priority list.
- VERIFICATION.md and HARDENING.md: historical evidence with stated boundaries. Do not present earlier tests as proof of a new commit.

Keep these roles distinct. Label unimplemented requirements and unverified behaviour honestly. Use one canonical description instead of copying the product brief into every instruction file.

## Delivery

Use a branch and PR for repository changes. Honour merge/release authorization already given in the active conversation; do not infer blanket publishing authority from this file. Keep v0.0.n previews until the maintainer chooses v0.1.0.

PRs should name the user problem, relevant acceptance scenario, verification performed and remaining gaps. For UI changes, include an actual screenshot or explain why capture was unavailable. Documentation-only changes need link/content checks, not new application tests. For code changes, run the relevant checks documented in README.md and satisfy CI; use live Omarchy acceptance for claims that headless tests cannot establish.
