# Security Remediation PR 1: Harness And Hook Trust

Status: Active

## Problem

The repository needs a safe trusted-base review path before later security work.
Harness validation follows repository source symlinks, contributor-controlled
checks can weaken themselves, plan status has drifted, and the local Kingfisher
hook verifies only a self-reported version after installation.

## Scope and non-goals

In scope: canonical untrusted-content guidance, trusted-main versus external-PR
startup, safe harness source enumeration, advisory sensitive-change reporting,
plan status ownership, and local hook installation/binary integrity.

Out of scope: Qt/runtime/archive implementation, privileged PR workflows,
GitHub setting changes, release publication, and prompt-injection keyword
scanning.

## Constraints and risks

- Preserve reviewed-main startup and docs-only cheap CI routing.
- Keep compatibility loaders thin and root `AGENTS.md` concise.
- Treat the sensitive-change report and local hook as advisory/defense in depth;
  human review, required CI, and push protection remain authoritative.
- Use Bash 3.2-compatible code, NUL-safe path handling, bounded reads, and no
  additional dependencies, secrets, write tokens, or jobs.
- Do not execute external/unreviewed checkout code on the maintainer workstation.

## Milestones

- [x] Add red harness and sensitive-diff fixtures.
- [x] Add trusted-base boundary, safe source collection, and advisory report.
- [x] Make plan header/index status canonical and remove stale docs status.
- [x] Harden hook trust, installed binary digest, uninstall, and purge.
- [x] Run focused/full local gates and review the diff.
- [ ] Commit and create the PR.
- [ ] Resolve one Copilot review, verify one hosted CI run, merge, and record PR 2 handoff.

## Verification

```bash
./tools/test_harness_security.sh
./tools/test_sensitive_change_report.sh
./tools/validate_harness.sh
./tools/test_ci_changed_paths.sh
./tools/test_ci_change_classification.sh
./tools/test_github_security.sh
./tools/test_git_hooks.sh
shellcheck .githooks/pre-commit tools/install_git_hooks.sh tools/validate_harness.sh tools/report_sensitive_changes.sh tools/test_harness_security.sh tools/test_sensitive_change_report.sh tools/test_git_hooks.sh
for script in .githooks/pre-commit tools/install_git_hooks.sh tools/validate_harness.sh tools/report_sensitive_changes.sh tools/test_harness_security.sh tools/test_sensitive_change_report.sh tools/test_git_hooks.sh; do bash -n "$script"; done
git diff --check
git status --short
```

## Progress

- 2026-08-27: Branch `security/pr1-harness-hooks` created at
  `647242590de0307db2fa7a373455b1e429578080`. Existing harness, CI path,
  GitHub security, and hook tests passed. Installed Kingfisher hash measured
  0.05 seconds over three runs.
- 2026-08-27: Red tests failed because the validator accepted an unsafe source
  and the sensitive reporter was absent. After implementation, harness source,
  sensitive report, GitHub policy, CI routing, and hook regressions pass.
- 2026-08-27: Verified all four Kingfisher 2.0.0 archive pins and derived stable
  executable hashes. Production checks use `/usr/bin/shasum`; the full hook
  integrity check measured 0.08 seconds over three runs.
- 2026-08-27: Full local gate passed: harness/source/report/CI/GitHub/hook/SBOM
  tests, Actionlint, Zizmor, ShellCheck, Bash syntax, and diff checks.
- 2026-08-27: Adversarial review added official-origin verification, protected
  `/usr/bin/shasum` and `/usr/bin/uname` resolution, plan/security-policy change
  reporting, bounded link-target diagnostics, and lower-noise content detection.

## Surprises & Discoveries

- `docs/exec-plans/TEMPLATE.md` has `Status: Active` as template content and
  must remain excluded from active-plan/status-index logic.
- Git does not enumerate untracked FIFOs through `git ls-files --others`, so the
  validator combines Git's regular/link inventory with a bounded filesystem
  pass for nonignored special files.

## Decision Log

- This repository plan owns active progress. External audit plans remain
  user-owned planning inputs and are not linked through machine-local paths.
- Keep one advisory report in the existing Ubuntu job; do not add a privileged
  or separate paid workflow.
- Use archive SHA-256 plus a separately pinned extracted-executable SHA-256 for
  each supported Kingfisher platform. Test-only hash substitution requires
  explicit hook test mode; production uses `/usr/bin/shasum`.
- Treat only the canonical upstream GitHub remote as default-trusted
  `origin/main`; forks and aliases require the exact reviewed-commit option.
- Combine the trusted-boundary and sensitive-report implementation in one
  buildable commit because validator markers, required files, and CI calls must
  land atomically. Keep hook integrity in its own commit.

## Outcomes & Retrospective

Implementation is in progress. Complete with commits, PR URL, local/hosted
verification, review disposition, residual risks, and the exact PR 2 base.
