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

- [Agent harness application](2026-04-29-agent-harness-application.md) -
  completed application of the harness methodology to this repo.
- [Installer diagnostics audit](2026-04-29-installer-diagnostics-audit.md) -
  completed audit of installer preview, diagnostics, and documentation behavior.
- [Community hardening](2026-04-28-community-hardening.md) - completed
  hardening pass for Qt package verification, reproducible packaging,
  diagnostics bundles, and backup manifest validation.
