# GitHub Security Deep Dive

Status: Active

## Problem

The repository already pins Actions and publishes checksummed, attested release
assets, but a fresh review against the OWASP GitHub Actions, CI/CD, supply-chain,
dependency, secrets, and SBOM guidance found controls that are documented but
not yet mechanically or host-enforced. The goal is to close those gaps without
making ordinary contribution, testing, or release recovery impractical.

## Scope and non-goals

In scope:

- Audit `.github/`, release automation, CODEOWNERS, Dependabot, security policy,
  public hosted settings, branch protection, action policy, contributor-run
  approval, secret scanning, CodeQL, releases, dependency inventory, and recent
  workflow evidence.
- Add fail-first local policy coverage for checkout credential persistence,
  bounded jobs, concurrency, immutable action refs, dangerous triggers,
  dependency cooldown, and safe release publication.
- Harden CI and release workflows while preserving existing runner platforms,
  regression coverage, manual release smoke capability, and tag publication.
- Add a path-scoped workflow security scan and future release notes/provenance
  evidence where it remains small and deterministic.
- Update security, trust, contribution, runbook, and changelog documentation.
- Read back any approved hosted setting mutation after applying it.

Out of scope:

- Game-bundle runtime behavior or another player release.
- Reading secret values, rotating Team17-owned credentials, or rewriting
  published Git history containing historical generic-key patterns.
- Enforcing admin branch protection or signed commits while one maintainer is
  the only required reviewer and local commits are not currently signed.
- Enabling paid services or organization-wide GitHub policy.

## Constraints and risks

- Preserve Bash 3.2 compatibility for shell checks and helpers.
- Keep every external Action pinned to an official full commit SHA and verify
  the corresponding tag/commit from the upstream repository.
- Do not expose the release token to checked-out Git credentials; publication
  should receive the token only in its owning step.
- Existing release recovery must remain possible after immutable releases are
  enabled: interrupted runs may resume a draft but must never overwrite a
  published release.
- External pull-request workflows execute repository test scripts. Requiring
  approval for all external contributors improves security but adds a small,
  intentional maintainer step.
- Hosted admin changes are reversible but affect repository-wide behavior and
  must be read before and after mutation.
- Avoid redundant hosted CI and security scans; consolidate changes and run one
  final remote verification only after local gates pass.

## Milestones

- [x] Milestone 1: Read the applicable cheat sheets and inventory local plus
  public hosted GitHub controls.
- [x] Milestone 2: Run actionlint, Zizmor, Dependabot/CodeQL state checks,
  release-state checks, and redacted current/history secret scans.
- [x] Milestone 3: Add fail-first policy and release-helper coverage.
- [x] Milestone 4: Harden workflows, dependency automation, release notes,
  release recovery, security scanning, and contributor/security templates.
- [x] Milestone 5: Run focused and full local repository verification plus one
  adversarial pass.
- [ ] Milestone 6: With exact approval, apply and verify the selected hosted
  Actions, scanning, contributor-approval, and release-immutability controls.
- [ ] Milestone 7: Commit/push only if requested, then verify the consolidated
  hosted checks without triggering redundant review or release workflows.

## Verification

```bash
./tools/test_github_security.sh
./tools/validate_harness.sh
actionlint .github/workflows/*.yml
zizmor --persona=pedantic --no-ignores --no-progress .github
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./tools/build_release_bundle.sh --version github-security-smoke --skip-zip
./scripts/download_qt_frameworks.sh --check
git diff --check
```

Full regression scripts remain the final local gate because CI configuration
changes must not silently drop existing behavior coverage.

## Progress

- 2026-08-26: Confirmed `main` is protected with current required CI checks,
  one approving CODEOWNER review, stale-review dismissal, strict status checks,
  conversation resolution, and force-push/deletion protection. Admin bypass is
  enabled to keep the sole-maintainer workflow usable.
- 2026-08-26: Confirmed default workflow tokens are read-only and cannot approve
  reviews; Dependabot updates, secret scanning, and push protection are enabled.
  No Actions/Dependabot secrets, variables, deploy keys, webhooks, open
  Dependabot alerts, or current-tree Gitleaks findings were present.
- 2026-08-26: Found contributor workflow approval limited to first-time
  contributors, Action SHA enforcement disabled at the hosted policy layer,
  immutable releases disabled, CodeQL default setup not configured, and the
  dependency-graph SBOM empty.
- 2026-08-26: Actionlint passed. Zizmor found checkout credential persistence,
  missing concurrency/time bounds, a direct workflow-output interpolation,
  missing deny-by-default release permissions, and Dependabot cooldown gaps.
- 2026-08-26: Redacted history scanning found six generic-key patterns in old
  `TEAM17_DEVELOPER_REPORT.md` revisions; the current tree is clean. Validity,
  rotation, and vendor ownership cannot be established without reading or
  disclosing secret values, so that remains an incident-response follow-up.
- 2026-08-26: Added a fail-first GitHub policy regression that reported 19
  missing controls, then made it pass with deny-by-default/job-scoped
  permissions, checkout isolation, concurrency/time bounds, safe expression
  handoff, cooldown, Zizmor, draft-first release recovery, and changelog notes.
- 2026-08-26: Added private vulnerability routing and a focused pull request
  template. Updated security, trust, contribution, runbook, changelog, harness,
  and plan indexes with the new behavior and residual risks.
- 2026-08-26: Verified every Action against its official latest stable tag and
  GitHub-verified commit. The complete local gate passed every repository
  regression, full ShellCheck/Bash syntax, actionlint, pedantic Zizmor with no
  findings, harness, Qt validation, release smoke, changelog extraction, AGL
  compilation, and diff checks.
- 2026-08-26: The adversarial pass found no material bypass in the updated
  workflows. Draft-only `--clobber` preserves interrupted-release recovery;
  published releases are refused. Residuals are hosted enforcement, historical
  credential-owner confirmation, standard SBOM publication, and the deliberate
  solo-maintainer branch bypass.

## Surprises & Discoveries

- GitHub's current immutable-release control is repository-level and requires
  draft-first publication so assets exist before the release becomes immutable.
- Manual release dispatch has been used, so removing it would reduce a real
  maintainer recovery/smoke path; permissions and publication conditions should
  be narrowed instead.
- Requiring branch protection for administrators would make a one-review,
  one-maintainer repository unable to merge its own pull requests without a
  second trusted reviewer.
- GitHub recognizes no package components for this shell/C repository even
  though the Qt archive has a 17-bottle checksum-locked provenance inventory.

## Decision Log

- Keep traditional `main` protection and its deliberate admin bypass until a
  second trusted reviewer exists; do not trade away repository usability for a
  control the current ownership model cannot satisfy.
- Preserve manual release dispatch, but make tag publication draft-first,
  resumable only while draft, and unable to overwrite a published release.
- Prefer a small path-scoped Zizmor workflow and repo-local policy test over
  broad new third-party CI dependencies.
- Keep the checksum-locked Qt provenance inventory and document the missing
  standard SBOM rather than introducing a new generator whose specification and
  dependency edges cannot be proven from the flat bottle lock.
- Treat hosted SHA enforcement, all-external contributor approval, CodeQL
  default setup, enhanced secret scanning, and immutable releases as separate
  read-mutate-read operations.

## Outcomes & Retrospective

Pending implementation and verification.
