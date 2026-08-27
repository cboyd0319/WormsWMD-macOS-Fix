# Open Pull Request Resolution

Status: Active

## Problem

Three pull requests remain open after v1.7.6. PR #21 proposes a narrower issue
#20 fix that conflicts with the shipped generic Mach-O resolution and complete
rollback work. Dependabot PRs #17 and #18 are behind `main`; #17 also targets an
`actions/attest` release that upstream has already superseded.

## Scope and non-goals

In scope:

- Confirm v1.7.6 covers PR #21's motivating GOG failure, respond to the
  contributor, and close the superseded pull request without merging it.
- Update every `actions/checkout` pin to the verified latest v7.0.1 tag target.
- Update `actions/attest` directly to the verified latest v4.2.2 tag target,
  superseding Dependabot PR #17's v4.2.1 proposal.
- Run focused local and hosted verification, then respond to and close PRs #17
  and #18 as applied or superseded.

Out of scope:

- New installer behavior, another release, or any release-asset mutation.
- Mutable action tags or broader workflow permissions.
- Deleting contributor or Dependabot branches.

## Constraints and risks

- Keep every external action pinned to a full immutable commit SHA.
- Resolve each SHA against the official upstream tag and require GitHub's
  verified commit signal before use.
- Preserve current workflow triggers, jobs, permissions, and inputs.
- Use one meaningful hosted CI run for the combined update instead of rebasing
  and building two stale dependency branches separately.
- Preserve contributor credit and explain the technical supersession clearly.

## Milestones

- [x] Milestone 1: Inventory every open PR, its diff, head/base state, checks,
  author, and requested outcome.
- [x] Milestone 2: Verify current upstream releases and immutable tag targets
  for `actions/checkout` and `actions/attest` from their official repositories.
- [x] Milestone 3: Apply the combined workflow update and pass local workflow,
  harness, syntax, pin, and diff checks.
- [ ] Milestone 4: Push the maintenance commit and require one hosted CI run to
  exercise the new checkout action.
- [ ] Milestone 5: Post specific maintainer responses, close PRs #17, #18, and
  #21, and confirm no open pull requests remain.

## Verification

```bash
actionlint .github/workflows/*.yml
./tools/validate_harness.sh
git diff --check
rg -n 'actions/(checkout|attest)@|actions/(checkout|attest) v' .github/workflows
```

Hosted verification requires all jobs in the single `main` CI run to pass.

## Progress

- 2026-08-26: Found PR #21 dirty against current `main`, with its motivating
  failure already resolved and released in v1.7.6 through generic `LC_RPATH`
  handling and broader transactional rollback coverage.
- 2026-08-26: Found PRs #17 and #18 green on their historical heads but behind
  current `main`. PR #17 targets attest v4.2.1, while official upstream state
  identifies v4.2.2 as the latest release.
- 2026-08-26: Verified checkout v7.0.1 resolves to signed commit
  `3d3c42e5aac5ba805825da76410c181273ba90b1` and attest v4.2.2 resolves to
  signed commit `1e69f48acb82d1966a394da916b4c1698aa569d6`.
- 2026-08-26: Baseline actionlint and harness checks passed before changing the
  workflow pins.
- 2026-08-26: Updated all four checkout sites and the release attestation site,
  including matching human-readable version comments. Actionlint, harness,
  exact occurrence, stale-pin absence, and diff checks passed.
- 2026-08-26: A local adversarial supply-chain pass found no material issue.
  Workflow triggers, jobs, permissions, runners, and action inputs are unchanged.
  The attest action executes only in a release workflow, so ordinary CI cannot
  exercise it; official verified-tag provenance and its unchanged input and
  permission contract are the available pre-release evidence.

## Surprises & Discoveries

- The open attest PR is not merely behind the repository; its requested v4.2.1
  version is also behind upstream v4.2.2.
- PR #21's diagnosis correctly identifies the executable-adjacent Galaxy
  layout, but rewriting a valid `@rpath` load is narrower than the released
  resolver and would discard the executable's intended Mach-O run-path model.

## Decision Log

- Apply the two current upstream action releases in one maintenance commit
  instead of merging stale PR heads or spending CI on separate rebases.
- Close PR #21 as superseded rather than attempting to merge two competing
  implementations of issue #20.
- Keep workflow permissions and behavior unchanged; only immutable action pins
  and their human-readable version comments move.

## Outcomes & Retrospective

Pending local checks, hosted CI, and hosted PR cleanup.
