# Worms W.M.D Agent Layer

This directory contains repo-local agent routing assets. Root `../AGENTS.md`
remains the primary instruction source.

## Inventory

- `CLAUDE.md`: compatibility layer for tools that discover `.agents/CLAUDE.md`.
- `rules/wormswmd-maintenance.md`: compact always-on maintenance rules.

## Routing

Use root `../AGENTS.md` first, then:

- `../docs/design/runtime-contracts.md` for installer, backup, network,
  diagnostics, and release invariants.
- `../docs/runbooks/agent-session.md` for startup, validation, diagnostics,
  handoff, and clean-state workflow.
- `../docs/style/agent-harness.md` for harness change rules.
- `../docs/exec-plans/` for active and historical execution plans.

## Maintenance

Keep this layer small. Move durable project facts to `../docs/` and use this
directory only for agent routing and rule-loader compatibility.
