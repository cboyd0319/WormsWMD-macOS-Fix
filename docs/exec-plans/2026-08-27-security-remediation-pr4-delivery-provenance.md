# Security Remediation PR 4: Delivery And Provenance

Status: Active

## Problem

The Qt artifact can currently self-approve related evidence, build-root Mach-O
paths prevent reproducibility, SBOM scope and scanner coverage are imprecise,
and release publication lacks protected-environment and main-ancestry gates.

## Scope and non-goals

In scope: component policy, scoped CycloneDX evidence, report-only scanner
coverage, Mach-O normalization, artifact comparison, TIFF probing, a protected
nonpublishing rebuild workflow, a libtiff-only 4.7.2 source lock, split release
privilege, and incident recovery documentation.

Out of scope: changing `dist` archive/checksum bytes, repository settings, tags,
releases, unrelated dependency versions, and independent-builder claims.

## Constraints and risks

- Branch from exact protected-main handoff
  `9416a3b6711c7d3fd5724728abf6f6ae6c52f534`.
- Keep PR 4 source-only; any `dist/*.tar.gz` or checksum change blocks delivery.
- The refreshed lock intentionally gets ahead of the current artifact; tag
  publication must fail until PR 5 restores lock/provenance equality.
- Manual rebuild is exact-main, cache-free, nonpublishing, and same-runner only.
- Scanner findings begin report-only, but tool failure, expired VEX, or zero
  parsed runtime inventory fail visibly.
- Use existing CI jobs where possible and one final hosted PR run unless a real
  correction changes the reviewed head.

## Milestones

- [x] Define all 17 component identities/scopes and prove policy failures.
- [x] Generate scoped SBOM evidence and actionable pinned scanner reports.
- [x] Normalize Mach-O paths, compare artifacts deeply, and prove TIFF runtime.
- [x] Add protected exact-main two-build nonpublishing rebuild evidence.
- [ ] Refresh only the reviewed libtiff 4.7.2 lock input.
- [ ] Split release privilege and add incident recovery.
- [ ] Run full local/adversarial gates, merge one reviewed PR, and record PR 5 base.

## Verification

```bash
/usr/bin/python3 tools/test_generate_sbom.py
/usr/bin/python3 tools/test_qt_vulnerability_policy.py
./tools/scan_qt_sbom.sh --local-report
./tools/test_qt_artifact_comparison.sh
./tools/test_qt_version_pinning.sh
./tools/test_qt_tiff_runtime.sh
./tools/test_github_security.sh
./tools/validate_harness.sh
actionlint .github/workflows/*.yml
zizmor --persona=pedantic --no-ignores --no-progress .github
shellcheck scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
test -z "$(git diff --name-only "$(git merge-base HEAD origin/main)" HEAD -- 'dist/*.tar.gz' 'dist/*.tar.gz.sha256')"
git diff --check
git status --short
```

## Progress

- 2026-08-27: Branch `security/pr4-delivery-provenance` created from exact
  protected-main handoff `9416a3b6711c7d3fd5724728abf6f6ae6c52f534`.
- 2026-08-27: Component policy covers 12 runtime and five build-only lock rows;
  runtime evidence exists in the inspected archive and every runtime identity
  has a reviewed NVD CPE mapping. Missing/duplicate/extra policy, evidence
  drift, invalid mapping, zero inventory, and stale/expired VEX regressions pass.
- 2026-08-27: Pinned Grype 0.117.0 parsed all 12 runtime components. Two local
  runs produced identical SBOM/report hashes and four report-only libtiff CPE
  matches with no suppression. Hosted burn-in remains part of the PR gate.
- 2026-08-27: All 35 current Mach-O files exposed 132 temporary/absolute load
  records. Packaging now canonicalizes IDs/imports, removes rpaths, and derives
  UUIDs from neutral bytes; two synthetic roots become hash-identical and the
  normalized current package validates. Deep exact/version-aware comparison
  rejects structural drift. A direct x86_64 QImageReader probe decoded a
  deterministic 1x1 TIFF against the current runtime under Rosetta.
- 2026-08-27: Manual rebuild workflow refuses non-main refs, checks exact HEAD,
  uses two separate caches/roots, requires byte-identical package evidence,
  deep comparison and TIFF success, then attests/uploads seven-day candidate
  evidence with read plus short-lived attestation scopes only.

## Surprises & Discoveries

- Current provenance has three relevant forms: the authoritative packaging
  lock, a versioned standalone file in `dist`, and the archive-embedded copy.
  Tag publication must require byte equality across all three.

## Decision Log

- The external six-PR program owns scope and order; this tracked plan owns repo
  progress and verification evidence.
- Version stays outside component policy; selected lock/provenance supplies it.
- Two clean builds on one hosted runner prove clean same-runner reproducibility,
  not independent builders.
- LC_UUID must be recomputed after path changes; changing load commands alone
  preserves UUID drift from the pre-normalized binary.
- No tag may be created between the PR 4 lock transition and PR 5 artifact merge.

## Outcomes & Retrospective

Implementation is in progress. Complete with PR URL, commits, local/hosted
evidence, scanner disposition, lock review, residual risks, and exact PR 5 base.
