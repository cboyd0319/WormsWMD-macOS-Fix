# Execution Plans

Execution plans are durable state for multi-step work. Use them when a task has
multiple files, material risk, unclear sequencing, or may need handoff to a new
agent.

## Required Shape

Start from [TEMPLATE.md](TEMPLATE.md). Every plan must keep these sections:

- `Problem`
- `Scope and non-goals`
- `Constraints and risks`
- `Milestones`
- `Verification`
- `Progress`
- `Surprises & Discoveries`
- `Decision Log`
- `Outcomes & Retrospective`

## Lifecycle

- Active work stays in this directory with `Status: Active`.
- Completed work stays in this directory with `Status: Completed` when it is
  useful as a future example or audit trail.
- Superseded plans stay in this directory with `Status: Superseded` and a link
  to the replacing plan.

Keep plans short enough to maintain. If the plan stops matching the work, update
the plan before continuing.

## Current Plans

- [Issue 20 GOG rpath and rollback hardening](2026-08-26-issue-20-gog-rpath-rollback.md) - completed
  fix for GOG dependency verification, transaction-safe rollback, backup
  identity, and correct multi-install diagnostics.
- [v1.7.5 release](2026-08-11-v1.7.5-release.md) - completed release prep,
  validation, publication, asset verification, and post-release bootstrap
  pinning.
- [Issue 19 QtCore bad file descriptor](2026-08-11-issue-19-qtcore-bad-fd.md) - completed
  fix for read-only copied Qt framework binaries on macOS 26.6.
- [v1.7.4 release](2026-07-01-v1.7.4-release.md) - completed release prep,
  validation, publication, asset verification, and post-release bootstrap
  pinning.
- [Post-1.7.3 audit fixes](2026-07-01-post-173-audit-fixes.md) - completed
  follow-up for installer detection, rollback, launcher, docs, harness
  tightening, live Steam validation, and final hardening.
- [v1.7.3 release](2026-06-29-v1.7.3-release.md) - completed release prep,
  publication, asset verification, and post-release bootstrap pinning.
- [Full repository deep audit](2026-06-29-full-repo-deep-audit.md) - completed
  repo-wide audit of installer, launcher, diagnostics, backup, release, CI, and
  documentation behavior.
- [Issue 12 AGL stub install failure](2026-06-29-issue-12-agl-stub-install.md) - completed
  fix for missing AGL and required Qt runtime partial installs.
- [macOS 27 Golden Gate compatibility](2026-06-22-macos-27-golden-gate.md) - completed
  full-repo compatibility and release-gate pass for macOS 27.
- [Issue 11 game detection](2026-06-22-issue-11-game-detection.md) - completed
  fix for Bash 3.2 strict-mode game discovery and GOG install detection.
- [v1.7.0 pre-release prep](2026-06-18-v1.7.0-pre-release.md) - completed
  release-tag and post-release bootstrap pinning.
- [Cheat sheet supply-chain hardening](2026-06-18-cheatsheet-supply-chain-hardening.md) - completed
  follow-up pass for Qt 5.15.x pinning, security cheat-sheet findings, and
  pre-release supply-chain readiness.
- [Issue 10 backup stall](2026-06-18-issue-10-backup-stall.md) - completed
  fix for silent backup manifest work, diagnostics privacy, and adjacent backup
  edge cases.
- [Deep repository audit](2026-06-10-deep-repo-audit.md) - completed
  repository-wide defect pass for installer, restore, verification, docs, and
  harness behavior.
- [Security hardening](2026-06-10-security-hardening.md) - completed
  repository-wide security pass for archive extraction, update downloads, CI
  pinning, LaunchAgent generation, and temporary build handling.
- [Agent harness application](2026-04-29-agent-harness-application.md) - completed
  application of the harness methodology to this repo.
- [Installer diagnostics audit](2026-04-29-installer-diagnostics-audit.md) - completed
  audit of installer preview, diagnostics, and documentation behavior.
- [Zero-technical release experience](2026-04-29-zero-technical-release.md) - completed
  release experience pass for the friendly launcher, release bundle, and
  support flow.
- [Community hardening](2026-04-28-community-hardening.md) - completed
  hardening pass for Qt package verification, reproducible packaging,
  diagnostics bundles, and backup manifest validation.
