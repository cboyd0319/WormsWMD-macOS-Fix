# Documentation Index

This index lists the durable documentation tracked in this repository. Keep it
current when adding, moving, renaming, or deleting Markdown files.

## Repository Entrypoints

- [Project README](../README.md) - user-facing overview, quick start, and
  support links.
- [Agent instructions](../AGENTS.md) - short map for coding agents.
- [Copilot instructions](../.github/copilot-instructions.md) - thin loader for
  Copilot-style agents.
- [Contributing](../CONTRIBUTING.md) - development setup, validation, and PR
  expectations.
- [Security](../SECURITY.md) - threat model, audit checklist, network policy,
  and security validation.
- [Changelog](../CHANGELOG.md) - released changes.
- [Team17 developer report](../TEAM17_DEVELOPER_REPORT.md) - technical report
  for the game vendor.

## User Guides

- [Installation](INSTALL.md) - manual install, dry-run, verify, and restore.
- [Troubleshooting](TROUBLESHOOTING.md) - common failures, logs, diagnostics,
  and recovery steps.
- [FAQ](FAQ.md) - common user and technical questions.
- [What this fix improves](IMPROVEMENTS.md) - feature and behavior overview.
- [Tools](TOOLS.md) - helper utility reference.
- [Technical details](TECHNICAL.md) - implementation details and limitations.

## Agent Harness

- [Runtime contracts](design/runtime-contracts.md) - architecture, data,
  network, and runtime invariants.
- [Agent session runbook](runbooks/agent-session.md) - startup, validation,
  diagnostic collection, handoff, and clean-state workflow.
- [Agent harness style](style/agent-harness.md) - repo-local harness engineering
  standard.
- [Execution plans](exec-plans/README.md) - plan lifecycle and required shape.
- [Execution plan template](exec-plans/TEMPLATE.md) - reusable plan scaffold.
- [Agent harness application plan](exec-plans/2026-04-29-agent-harness-application.md)
  - shipped plan for applying the harness methodology to this repo.
- [Installer diagnostics audit plan](exec-plans/2026-04-29-installer-diagnostics-audit.md)
  - audit trail for installer, diagnostics, and documentation fixes.
- [Community hardening plan](exec-plans/2026-04-28-community-hardening.md)
  - audit trail for Qt package verification, reproducible packaging,
    diagnostics bundles, and backup manifest validation.

## Maintenance

Run the harness check after documentation topology changes:

```bash
./tools/validate_harness.sh
```

The check verifies that this index links every tracked Markdown file, that local
Markdown links resolve, and that required harness entrypoints exist.
