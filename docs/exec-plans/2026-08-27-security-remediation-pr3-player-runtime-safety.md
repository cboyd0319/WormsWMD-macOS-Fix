# Security Remediation PR 3: Player And Runtime Safety

Status: Active

## Problem

Save restore, extracted Qt cache reuse, dependency copying, signature and
quarantine reporting, update downloads, traces, diagnostics, crash output, and
LaunchAgent updates retain player-facing trust or rollback gaps.

## Scope and non-goals

In scope: exact save destination containment and rollback, archive-authoritative
Qt caches, canonical dependency roots, strict classified signatures, recursive
bounded quarantine state, exact update checksums, and atomic owned local output.

Out of scope: real save mutation, `dist` rebuilds, libtiff updates, GitHub
settings, tags, release publication, and PR 4 delivery/provenance work.

## Constraints and risks

- Keep old data until replacement verification succeeds; rollback is explicit.
- Do not restore a real save archive during development.
- Preserve standard Homebrew `opt` links and explicitly trusted custom roots.
- Preserve diagnosis of original unsigned apps while rejecting invalid fixed apps.
- Do not alter the installer's strict signature check inside rollback.
- Use the existing CI jobs and one final remote run unless a real fix changes HEAD.

## Milestones

- [x] Contain save restore destinations and prove rollback.
- [x] Authenticate Qt cache reuse against archive authority.
- [x] Contain Homebrew dependency sources canonically.
- [ ] Classify strict signatures and recursive quarantine.
- [ ] Bind update downloads to exact checksums and atomic publish.
- [ ] Harden traces, diagnostics, crashes, and LaunchAgent updates.
- [ ] Run local and adversarial gates, merge one reviewed PR, and record PR 4 base.

## Verification

```bash
./tools/test_backup_saves_regression.sh
./tools/test_qt_cache_integrity.sh
./tools/test_dependency_parsing.sh
./tools/test_qt_version_pinning.sh
./tools/test_signature_verification.sh
./tools/test_preflight_regression.sh
./tools/test_installer_rollback_regression.sh
./tools/test_update_download_safety.sh
./tools/test_logging_safety.sh
./tools/test_launcher_friction.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_mutation_safety.sh
./tools/test_manifest_regression.sh
shellcheck fix_worms_wmd.sh scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
git diff --check
git status --short
```

## Progress

- 2026-08-27: Branch `security/pr3-player-runtime-safety` created from exact
  protected-main handoff `2dbbb52905c0b1d9b48fbb81658c15d7f0c1c3fc`.
- 2026-08-27: Existing save, dependency, Qt, preflight, rollback, launcher,
  support-bundle, mutation, manifest, harness, syntax, and ShellCheck baselines
  passed before behavior changes.
- 2026-08-27: Save restore now validates canonical numeric-user destinations,
  requires exact one-shot trust for external `327030`, stages every root on its
  target filesystem, checks Steam state, verifies all replacements, and rolls
  every applied root back on failure. Synthetic path, copy, verification, and
  rollback-failure regressions pass; no real save archive was restored.
- 2026-08-27: Qt caches now use the full archive digest, verify their manifest
  against the inspected archive on every reuse, and publish from same-parent
  `0700` staging. Legacy archives always regenerate; valid version-only caches
  are retained and pruned only by marker. Foreign, mode, interruption,
  missing-authority, and forged-manifest regressions pass. No-network warm reuse
  measured 3 seconds locally.
- 2026-08-27: One shared dependency resolver now rejects lexical traversal,
  linked/hardlinked/non-x86 sources, external roots, ambiguity, and basename
  conflicts while preserving loader-owned rpaths, spaces, custom roots, and the
  canonical Intel Cellar. Runtime copying and packaging share the policy. The
  installed Steam app completed read-only verification with zero findings after
  excluding each Mach-O image's own install ID.

## Surprises & Discoveries

- PR 2 handoff found two fixed-Steam plugin self-install-ID false positives;
  preserve rejection of other relative dependencies while correcting them.
- A separate `/Applications` installation remains intentionally unfixed.

## Decision Log

- The external six-PR plan owns scope and order; this tracked plan owns repo
  progress and evidence.
- Destructive save/cache changes land only with staged rollback tests.
- The existing macOS CI job already runs `test_backup_saves_regression.sh`; no
  workflow edit is needed merely to run its expanded fixtures.
- The cache marker is internal to the atomically renamed directory and binds
  canonical published path plus full archive digest; archive bytes remain the
  manifest authority.
- Dependency source policy is canonical and shared; copied bundle targets have
  a separate in-bundle regular-file/x86_64 check before reuse.

## Outcomes & Retrospective

Implementation is in progress. Complete with PR URL, commits, local and hosted
verification, rollback evidence, residual risks, and exact PR 4 base.
