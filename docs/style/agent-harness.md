# Agent Harness Style

Harness engineering is the repo-local system around coding agents: context,
constraints, tools, state, validation, observation, and review. For this repo,
the rule is simple: make the project legible, keep work bounded, and make
correctness observable from files and commands in the repository.

## Entry Points Stay Short

- `AGENTS.md` is a map, not a manual.
- Tool-specific files such as `.github/copilot-instructions.md` should load the
  shared entrypoints instead of duplicating rules.
- Deeper detail belongs in `docs/design/`, `docs/runbooks/`, `docs/style/`, and
  `docs/exec-plans/`.

## Durable Knowledge Is Split By Purpose

- `docs/design/` stores architecture, runtime contracts, data contracts, and
  source-of-truth decisions.
- `docs/runbooks/` stores operational workflows, recovery paths, diagnostics,
  release steps, and handoff procedures.
- `docs/style/` stores reusable engineering rules.
- `docs/exec-plans/` stores active, shipped, and superseded execution plans.

Do not turn one global instruction file into a long rulebook. Add the smallest
artifact that fixes the observed failure.

## Plans Are First-Class State

Use an execution plan for multi-step work, risky changes, cross-file behavior,
or anything that another agent may need to resume. A useful plan names:

- The problem and scope.
- Constraints and risks.
- Exact files expected to change.
- Milestones and current progress.
- Verification commands and exit conditions.
- Surprises, decisions, and final outcome.

Plans must be updated as reality changes. A stale plan is worse than no plan
because it gives the next worker false confidence.

## Convert Repeat Failures Into Checks

Prefer checks over reminders when the failure can be detected locally. Good
checks for this repo include:

- Shell syntax checks with `bash -n`.
- ShellCheck for scripts.
- AGL stub compilation with `clang`.
- `./tools/validate_harness.sh` for docs topology and local links.
- Dry-run, verify, preflight, and diagnostics commands on a macOS machine with
  the game installed.

Avoid broad style checks unless they protect a real invariant.

## Make Runtime Observation Local

Agents need local evidence, not only advice. When debugging, collect or point to:

- Fix logs under `~/Library/Logs/WormsWMD-Fix/`.
- Launcher logs and crash reports under `~/Library/Logs/WormsWMD/`.
- Diagnostics from `./tools/collect_diagnostics.sh`.
- Preflight output from `./tools/preflight_check.sh`.
- Exact command output for failed validation.

Do not paste secrets or unredacted private config values into docs, issues, or
reports.

## Review The Harness

Outdated instructions, broken links, stale validation claims, and hidden manual
steps are harness bugs. Before claiming a harness change is complete:

- Run `./tools/validate_harness.sh`.
- Confirm `docs/README.md` links all durable Markdown files.
- Remove duplicate or obsolete instructions instead of adding another layer.
- Keep validation counts out of durable docs; record commands and outcomes
  instead.
