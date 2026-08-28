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
- [x] Refresh only the reviewed libtiff 4.7.2 lock input.
- [x] Split release privilege and add incident recovery.
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
- 2026-08-27: Raw refresh proposed eight changed rows; review retained only the
  required libtiff 4.7.2 row and left all other inputs byte-identical to shipped
  provenance. A full isolated 17-bottle fetch exposed and fixed staging-path
  relocation plus safe contained soname aliases. Local candidate `90c0d19e...`
  is x86_64, canonical, embeds the curated lock, and passes comparison/TIFF.
- 2026-08-27: Manual release dispatch is read-only. A second read-only tag job
  proves ancestry and checksum/ZIP-manifest/three-way-provenance/SBOM evidence.
  Only then does the `release` environment job receive scoped write/attestation
  permissions. Incident recovery covers signed tags, keys, rules, workflow
  disablement, evidence, withdrawal, corrective notice, and publication.
- 2026-08-27: Adversarial review added the policy-parser scan trigger, moved all
  verification into a read-only middle job before publish scopes exist, made
  absent/unreviewed release environment settings fail closed while preserving
  the approved sole-maintainer approval path, requires exact source-rebuilt
  release content/modes and artifact inventory, bounds comparator evidence,
  rechecks the live tag object, and rejects extra resumed-draft assets. Scanner
  classification now covers every transitive implementation dependency.
- 2026-08-27: Fresh complete local verification passed, including all Python,
  shell, Ruby, harness, workflow, archive, cache, runtime, comparison, TIFF,
  Kingfisher, Semgrep, ShellCheck, Actionlint, Zizmor, and x86_64 compile gates.
  Two scans again produced SBOM `ba5880d...` and report `a204b087...`, with 12
  mapped runtime components and four report-only libtiff matches. The source-only
  dist guard passed. Steam passes strict verification; the installed GOG copy is
  preserved as an unfixed baseline for PR 5's protected-artifact runtime gate.
- 2026-08-27: The single Copilot review produced three valid findings. Invalid
  UTF-8 now becomes a bounded policy error, normalized scan evidence requires
  pinned Grype identity, `--by-cve`, the exact SBOM source and runtime mapping,
  and release ZIPs require Unix mode metadata. New red regressions and the full
  local gate passed, followed by one consolidated correction push and green
  final hosted checks.
- 2026-08-27: PR 28 merged as `7f607071...` after final hosted checks passed.
  Protected rebuild 33131306511 correctly withheld artifacts when clean archives
  differed because metadata embedded `prefix-one` versus `prefix-two`. The
  corrective workflow now supplies one stable source label. Before any new
  hosted run, the exact two-cache/two-prefix build completed locally with both
  archives at `7caf51f4...`; checksum/provenance, deep comparison, 35 canonical
  Mach-O files, TIFF decode, libtiff 4.7.2 ABI, and candidate SBOM/Grype parsing
  all passed with no retained build path.

## Surprises & Discoveries

- Current provenance has three relevant forms: the authoritative packaging
  lock, a versioned standalone file in `dist`, and the archive-embedded copy.
  Tag publication must require byte equality across all three.
- Bottle relocation originally embedded the temporary staging prefix before
  publishing it. Relocation now targets the canonical final output and rejects
  any staging path left in Mach-O metadata.
- Locked Homebrew sonames can be contained leaf symlinks. Resolution now
  canonicalizes the alias, then applies existing root, regular-file, single-link,
  and x86_64 checks to the target; escaping aliases still fail.

## Decision Log

- The external six-PR program owns scope and order; this tracked plan owns repo
  progress and verification evidence.
- Version stays outside component policy; selected lock/provenance supplies it.
- Two clean builds on one hosted runner prove clean same-runner reproducibility,
  not independent builders.
- LC_UUID must be recomputed after path changes; changing load commands alone
  preserves UUID drift from the pre-normalized binary.
- No tag may be created between the PR 4 lock transition and PR 5 artifact merge.
- Current formula resolution is evidence, not authority; dependency/tap churn
  is rejected unless the refreshed bottle requires it for compatibility.
- Release uses three jobs rather than two so write/attestation scopes do not
  exist until a read-only verification job has succeeded.

## Outcomes & Retrospective

Implementation is in progress. Complete with PR URL, commits, local/hosted
evidence, scanner disposition, lock review, residual risks, and exact PR 5 base.
