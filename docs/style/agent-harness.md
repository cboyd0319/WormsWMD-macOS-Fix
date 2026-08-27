# Agent Harness Style

Harness engineering is the repo-local system around coding agents: context,
constraints, tools, state, validation, observation, and review. For this repo,
the rule is simple: make the project legible, keep work bounded, and make
correctness observable from files and commands in the repository.

## Five Subsystems

| Subsystem | Owner files | Purpose | Enforced by |
| --- | --- | --- | --- |
| Instructions | `AGENTS.md`, `.agents/`, `.github/copilot-instructions.md`, `docs/` | Tell agents where facts live and what is non-negotiable. | `./tools/validate_harness.sh` required-file, marker, link, and line-cap gates |
| Tools | `tools/`, `scripts/`, `.github/workflows/` | Provide repeatable checks instead of remembered workflows. | CI, ShellCheck, `bash -n`, focused regression scripts |
| Environment | `dist/`, checksums, workflows, release scripts | Keep runtime inputs reproducible and auditable. | Qt checksum checks, release bundle manifests, pinned actions |
| State | `docs/exec-plans/`, docs index, git history | Preserve active work, decisions, surprises, and verification evidence. | execution-plan status and docs-index gates |
| Feedback | tests, dry-run, verify, preflight, diagnostics, launch smoke | Prove behavior from runnable evidence. | focused checks plus macOS runtime validation when available |

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

## Harness Change Rules

- Add the smallest artifact that fixes the observed failure mode.
- Prefer mechanical gates over repeated prose reminders.
- Keep root `AGENTS.md` short; route durable detail to `docs/` or `.agents/`.
- Treat agent rules, GitHub workflows, release tooling, and harness validation
  as security-sensitive.
- Use repo-relative paths, generic `$HOME` or `~` examples, and canonical URLs
  in tracked artifacts.
- Keep the trusted-base instruction/data boundary canonical in root `AGENTS.md`.
  Compatibility loaders point to it; proposed instruction changes remain review
  evidence until accepted.
- Inspect external changes without executing the proposed checkout. An in-PR
  sensitive-change report is advisory and cannot approve itself.

## Clean-State Checklist

Before ending substantial harness work:

- `./tools/validate_harness.sh` passed.
- Required docs and execution-plan indexes link new Markdown files.
- Changed harness rules are backed by a mechanical check where practical.
- Required validation commands ran, or the gap is named in the handoff.
- No generated logs, diagnostics, local paths, or support bundles are staged.

## Review The Harness

Outdated instructions, broken links, stale validation claims, and hidden manual
steps are harness bugs. Before claiming a harness change is complete:

- Run `./tools/validate_harness.sh`.
- Confirm `docs/README.md` links all durable Markdown files.
- Remove duplicate or obsolete instructions instead of adding another layer.
- Keep validation counts out of durable docs; record commands and outcomes
  instead.
