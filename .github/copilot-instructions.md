# Copilot Instructions

Use `../AGENTS.md` as the primary agent entrypoint for this repository.

Before editing, read:

- `../docs/README.md`
- `../docs/design/runtime-contracts.md`
- `../docs/runbooks/agent-session.md`
- `../docs/style/agent-harness.md`
- `../.agents/rules/wormswmd-maintenance.md`

For multi-step work, create or update an execution plan under
`../docs/exec-plans/` using `../docs/exec-plans/TEMPLATE.md`.

When harness docs or Markdown links change, run:

```bash
./tools/validate_harness.sh
```
