# Agent Harness Application

Status: Completed

## Problem

The repo has strong product docs and shell validation, but it lacks a durable
agent entrypoint, a complete docs index, an execution-plan standard, and a local
check that keeps those harness artifacts discoverable.

## Scope and non-goals

In scope:

- Add `AGENTS.md` as a short repo map for coding agents.
- Add `.github/copilot-instructions.md` as a thin loader.
- Add `docs/README.md` as the tracked documentation index.
- Add harness docs under `docs/design/`, `docs/runbooks/`, `docs/style/`, and
  `docs/exec-plans/`.
- Add `tools/validate_harness.sh` and wire it into CI.
- Update `README.md` and `CONTRIBUTING.md` to point at the harness docs.

Non-goals:

- Change the Worms W.M.D fix behavior.
- Change the Qt archive in `dist/`.
- Add new runtime dependencies to the installer.

## Constraints and risks

- The repo is public and user-facing, so agent docs must not obscure the quick
  install path.
- Validation must run on both local macOS shells and GitHub Actions.
- The harness should be thin enough to maintain and must not duplicate the full
  contents of existing user docs.

## Milestones

- [x] Add short agent entrypoints.
- [x] Add the docs index and harness documentation topology.
- [x] Add a deterministic harness validation script.
- [x] Wire the validation script into CI.
- [x] Run validation and update this plan with outcomes.

## Verification

Planned commands:

```bash
./tools/validate_harness.sh
for script in fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
```

Run ShellCheck if it is installed locally.

## Progress

- 2026-04-29: Started applying the agent harness methodology to this repo.
- 2026-04-29: Added agent entrypoints, harness docs, execution-plan standards,
  and CI-backed harness validation.

## Surprises & Discoveries

- The repo already had user docs for install, troubleshooting, tools, technical
  details, security, and contribution, but no physical `AGENTS.md` or docs
  index.

## Decision Log

- Use a Bash harness validator so it matches the repo's existing shell-first
  toolchain.
- Keep agent-specific detail in docs instead of expanding the root README.

## Outcomes & Retrospective

Shipped a repo-local agent harness without changing product runtime behavior.
Validation completed with:

```bash
./tools/validate_harness.sh
for script in fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
```
