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
