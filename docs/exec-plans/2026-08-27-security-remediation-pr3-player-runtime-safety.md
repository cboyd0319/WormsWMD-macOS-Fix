# Security Remediation PR 3: Player And Runtime Safety

Status: Completed

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
- [x] Classify strict signatures and recursive quarantine.
- [x] Bind update downloads to exact checksums and atomic publish.
- [x] Harden traces, diagnostics, crashes, and LaunchAgent updates.
- [x] Run local and adversarial gates, merge one reviewed PR, and record PR 4 base.

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
  escaping aliases, hardlinked/non-x86 sources, external roots, ambiguity, and
  basename conflicts while preserving loader-owned rpaths, contained soname
  aliases, spaces, custom roots, and the canonical Intel Cellar. Runtime copying
  and packaging share the policy. The
  installed Steam app completed read-only verification with zero findings after
  excluding each Mach-O image's own install ID.
- 2026-08-27: Shared strict classification now derives complete-fixed state
  from the AGL/Qt/plugin surface, uses deep/strict codesign verification, and
  recursively counts quarantine without filenames. Unit and consumer tests pass.
  Read-only live state is `fixed-valid-adhoc`/`none` for Steam and
  `original-unsigned`/`none` for the unfixed `/Applications` copy.
- 2026-08-27: Update downloads now accept one bounded checksum record naming
  the exact release zip, reject control bytes and unsafe existing targets, and
  stage both artifacts owner-only before rollback-aware publication. Text and
  binary records, decoys, extra records, NUL/CR controls, mismatches,
  interruption, replacement, links, hardlinks, FIFOs, and temp cleanup pass.
- 2026-08-27: Debug traces are new, private, path-classified files; diagnostics
  and uniquely named crashes publish private same-directory staging files.
  Watcher plist install/uninstall now validates exact ownership, type, label,
  program, and syntax, and a forced bootstrap failure restores and reactivates
  the prior agent. Linked, foreign, collision, and rollback regressions pass.
- 2026-08-27: Adversarial review found and corrected premature save-transaction
  state, omitted executable-owned fallback rpaths, stale bundled dependency
  reuse, a Qt-version-blind fixed-state predicate, and a conditional-call
  control-path check. Each correction has a fail-first regression; fresh full
  local verification passed across all PR3, harness/security, CI-classifier,
  SBOM/archive/bottle, hook/bootstrap/issue, ShellCheck, and syntax gates.
- 2026-08-27: The one requested Copilot review identified duplicated update
  target validation. The checker now calls the shared exact-string validator;
  its focused test and the affected local gates pass before the corrective push.
- 2026-08-27: [PR #27](https://github.com/cboyd0319/WormsWMD-macOS-Fix/pull/27)
  merged after GitHub Security run 17 and CI run 116 passed on corrected head
  `33968c6e737f7d974d12962165fb5d52871a1c47`. Merge commit
  `7b10f3eb9e487fe8a7ec88499735ae093870e189` is followed by this closeout;
  PR 4 must start from the latest protected `main` including the closeout.

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
- Original/unfixed signature failures remain repairable warnings; complete fixed
  failures or unavailable verification are errors. Installer rollback signing
  stays unchanged.
- Release checksum records are parsed as data and bound to the expected basename;
  remote checksum text is never executed through checksum-tool path semantics.
- Local output uses destination-side staging and private modes; the watcher
  retains its verified prior plist until replacement bootstrap succeeds.
- Restore rollback state is set before each rename but interpreted with
  filesystem evidence, so failure before retention cannot delete the original.

## Outcomes & Retrospective

Six planned commits merged through PR #27. Full local and hosted gates passed,
one Copilot finding was fixed and resolved, and no real save was restored or
mutated. Save and LaunchAgent failure fixtures prove retained-state rollback;
cache and dependency fixtures prove authority and containment. Residual risk is
limited to ordinary same-user races and final player compatibility checks. PR 4
starts from the latest protected `main`, including this closeout record.
