# Documentation Index

This index lists the durable documentation tracked in this repository. Keep it
current when adding, moving, renaming, or deleting Markdown files.

## Repository Entrypoints

- [Project README](../README.md) - user-facing overview, quick start, and
  support links.
- [Support](../SUPPORT.md) - community support flow and support bundle guidance.
- [Steam forum post template](../STEAM_POST.md) - copy/paste player support
  text.
- [Attributions and asset policy](../ATTRIBUTIONS.md) - unofficial-project
  status and bundled asset policy.
- [Agent instructions](../AGENTS.md) - short map for coding agents.
- [Copilot instructions](../.github/copilot-instructions.md) - thin loader for
  Copilot-style agents.
- [Contributing](../CONTRIBUTING.md) - development setup, validation, and PR
  expectations.
- [Security](../SECURITY.md) - threat model, audit checklist, network policy,
  and security validation.
- [Trust and safety](TRUST.md) - release verification, provenance checks, and
  why the fix can be reviewed before it is run.
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
- [Assets](../assets/README.md) - original visual assets and asset rules.

## Agent Harness

- [Runtime contracts](design/runtime-contracts.md) - architecture, data,
  network, and runtime invariants.
- [Agent session runbook](runbooks/agent-session.md) - startup, validation,
  diagnostic collection, handoff, and clean-state workflow.
- [Agent harness style](style/agent-harness.md) - repo-local harness engineering
  standard.
- [Execution plans](exec-plans/README.md) - plan lifecycle and required shape.
- [Execution plan template](exec-plans/TEMPLATE.md) - reusable plan scaffold.
- [Deep repository audit plan](exec-plans/2026-06-10-deep-repo-audit.md) -
  completed audit trail for the repository-wide defect pass.
- [Issue 10 backup stall plan](exec-plans/2026-06-18-issue-10-backup-stall.md)
  - completed fix for silent backup manifest work, diagnostics privacy, and
    adjacent backup edge cases.
- [Issue 11 game detection plan](exec-plans/2026-06-22-issue-11-game-detection.md)
  - completed fix for Bash 3.2 strict-mode game discovery and GOG install
    detection.
- [macOS 27 Golden Gate compatibility plan](exec-plans/2026-06-22-macos-27-golden-gate.md)
  - completed full-repo compatibility and release-gate pass for macOS 27.
- [Cheat sheet supply-chain hardening plan](exec-plans/2026-06-18-cheatsheet-supply-chain-hardening.md)
  - completed follow-up for Qt 5.15.x pinning, security cheat-sheet findings,
    and pre-release supply-chain readiness.
- [v1.7.0 pre-release prep plan](exec-plans/2026-06-18-v1.7.0-pre-release.md)
  - completed deterministic version, changelog, documentation, and validation
    prep before final release commit pinning.
- [Security hardening plan](exec-plans/2026-06-10-security-hardening.md) -
  completed audit trail for repository-wide security hardening.
- [Agent harness application plan](exec-plans/2026-04-29-agent-harness-application.md)
  - shipped plan for applying the harness methodology to this repo.
- [Installer diagnostics audit plan](exec-plans/2026-04-29-installer-diagnostics-audit.md)
  - audit trail for installer, diagnostics, and documentation fixes.
- [Zero-technical release experience plan](exec-plans/2026-04-29-zero-technical-release.md)
  - audit trail for the friendly launcher, release bundle, and support flow.
- [Community hardening plan](exec-plans/2026-04-28-community-hardening.md)
  - audit trail for Qt package verification, reproducible packaging,
    diagnostics bundles, and backup manifest validation.

## Maintenance

Run the harness check after documentation topology changes:

```bash
./tools/validate_harness.sh
```

The check verifies that this index links every tracked Markdown file, that local
Markdown links resolve, that accidental local machine paths stay out of tracked
text, and that required harness entrypoints exist.
