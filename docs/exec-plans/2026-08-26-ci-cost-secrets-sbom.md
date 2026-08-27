# CI Cost, Secret Scanning, and Release SBOM

Status: Active

## Problem

The GitHub security pass made every workflow explicit and bounded, but the
current CI still starts two macOS jobs in parallel for every change, including
documentation-only updates. The security workflow does not scan the current
tree for non-provider secrets, and releases publish custom Qt provenance but no
standard SBOM. The next pass must reduce wasted compute without weakening the
required security and runtime evidence.

## Scope and non-goals

In scope:

- Apply the supplied CI cost guidance where it matches measured repository
  behavior: cancel stale runs, group short jobs, chain cheap checks before
  macOS, skip macOS validation for allowlisted non-runtime changes, and retain
  artifacts briefly.
- Merge AGL compilation into the existing macOS regression job so one macOS
  runner proves both contracts.
- Add MongoDB Kingfisher v2.0.0 current-tree scanning to the existing required
  GitHub security job using a checksum- and attestation-verified release binary.
- Keep historical Team17-controlled values out of the blocking scan by scanning
  the current checkout rather than Git history; disable live validation so
  candidates are not sent to providers.
- Generate a deterministic CycloneDX 1.6 SBOM from the existing 17-entry
  checksum-locked Homebrew provenance file, publish it with every release, and
  bind the release zip to it with GitHub's official SBOM attestation support.
- Update focused tests, security/trust/release docs, changelog, and execution
  plans.

Out of scope:

- Dependency or build caches in privileged release/security workflows.
- Self-hosted runners, merge queues, paid runner changes, or billing settings.
- Historical secret scanning, vendor credential validation/revocation, or Git
  history rewriting.
- Replacing the shipped Qt archive or changing runtime behavior.

## Constraints and risks

- Preserve all 13 existing regressions and Bash 3.2/macOS runtime coverage for
  any change that can affect executable behavior.
- Documentation-only and issue/template changes may skip macOS only after
  ShellCheck, Bash syntax, harness, GitHub policy, Zizmor, and Kingfisher remain
  required and green.
- Change classification must fail safe: unknown paths require macOS.
- Do not cache untrusted secret-scanner rules or binaries across pull requests.
- Kingfisher must use the official verified v2.0.0 tag and release asset with SHA-256
  `d30d71f82e25e8c024f98cce3258c90e17b5be31d0fdb6f30b438d2fac1f130b`
  before execution. GitHub reports an attestation for this digest, but local
  `gh attestation verify` returned `promptError`, so checksum verification is
  the deterministic execution gate.
- The SBOM parser must bound input, reject duplicate/malformed lock rows, use
  HTTPS distribution URLs, validate every SHA-256, and write atomically.
- The SBOM must describe only relationships proven by the flat lock: the
  release package depends on the complete component set, without inventing
  component-to-component edges.

## Milestones

- [x] Milestone 1: Read all four cost sources and current Kingfisher/CycloneDX
  primary documentation; map applicable and rejected recommendations.
- [x] Milestone 2: Add fail-first macOS classification, Kingfisher policy, and
  deterministic SBOM tests.
- [x] Milestone 3: Consolidate and chain CI, integrate Kingfisher, and add SBOM
  generation/publication/attestation.
- [x] Milestone 4: Update documentation and hosted required-check configuration.
- [ ] Milestone 5: Run focused/full local gates, one adversarial pass, and one
  meaningful PR check set before merge.

## Verification

```bash
./tools/test_ci_change_classification.sh
python3 tools/test_generate_sbom.py
./tools/test_github_security.sh
./tools/validate_harness.sh
actionlint .github/workflows/*.yml
zizmor --persona=pedantic --no-ignores --no-progress .github
kingfisher scan . --redact --no-validate --confidence medium --quiet --no-update-check
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./tools/build_release_bundle.sh --version ci-cost-smoke --skip-zip
git diff --check
```

The complete 13-script regression set remains mandatory locally and in the
single macOS job whenever the fail-safe classifier reports a runtime change.

## Progress

- 2026-08-26: The supplied cost sources consistently recommend canceling stale
  runs, path awareness, grouping short jobs, chaining cheap-to-expensive gates,
  bounded artifact retention, right-sized runners, and early automated security
  checks. Caching was rejected for privileged release/security jobs because the
  security guidance treats cross-run cache poisoning as a higher risk.
- 2026-08-26: Measured PR #23 at 12 seconds Ubuntu ShellCheck, 17 seconds Ubuntu
  Zizmor, 20 seconds in a separate macOS C job, and 3 minutes 29 seconds in the
  macOS regression job. The separate C runner can be eliminated.
- 2026-08-26: Verified Kingfisher v2.0.0 is the latest release. Its Linux x64
  archive publishes the pinned SHA-256 above and SLSA/GitHub attestations. A
  local current-tree scan is clean; historical vendor-controlled values are not
  required for preventing new repository leaks.
- 2026-08-26: Selected CycloneDX 1.6 JSON because it supports a release root
  component, component hashes, source URLs, custom provenance properties, and a
  root dependency set without claiming unavailable internal edges.
- 2026-08-26: Added fail-first tests for macOS change classification,
  deterministic SBOM output/input rejection, and enforced Git hooks. The tests
  failed for the missing implementations, then passed after the changes.
- 2026-08-26: Added a versioned pre-commit hook and checksum-pinned installer,
  configured this checkout's `core.hooksPath=.githooks`, and installed
  Kingfisher 2.0.0 under the local Git directory. Staged scans fail closed,
  redact output, disable history/live validation, and remain backed by CI.
- 2026-08-26: Merged C compilation into the macOS regression job, chained it
  behind the Ubuntu gate, and added a fail-safe path classifier so allowlisted
  docs/community changes skip macOS while unknown/runtime paths do not.
- 2026-08-26: Added current-tree Kingfisher to the existing Zizmor runner using
  the pinned v2.0.0 Linux asset. No cross-run cache is used.
- 2026-08-26: Added a standard-library CycloneDX generator for the locked Qt
  closure, release upload plus SBOM attestation, and deterministic/error tests.
  A generated v1.7.6 document passed the official CycloneDX 1.6 JSON schema.
- 2026-08-26: The first full Kingfisher run found a false positive inside its
  own locally installed `.git/tools/kingfisher` binary. Both hook and CI scans
  now exclude Git internals while continuing to scan all staged/current source.
- 2026-08-26: The adversarial review found two fail-open/semantic defects before
  publication: failed `git diff` classification could skip macOS, and the SBOM
  root used the Qt archive hash instead of the release zip hash. Diff failures
  now force macOS; the SBOM takes the built zip checksum as a required input and
  records the Qt archive checksum separately as provenance metadata.
- 2026-08-26: All existing regressions, hook/security/classifier/SBOM tests,
  ShellCheck/Bash syntax, Ruff, actionlint, pedantic Zizmor, harness, Qt check,
  current-tree Kingfisher, AGL compile, release zip checksum, and diff checks
  passed. A real generated SBOM validated against the official CycloneDX 1.6
  schema and its root hash matched the release zip.
- 2026-08-26: Replaced the obsolete standalone `Validate C Code` branch context
  with the unchanged required `Validate Scripts` context that now owns the same
  compilation. ShellCheck and Zizmor remain required with strict current checks.
- 2026-08-26: Rewrote `SECURITY.md` as a shorter security contract organized by
  posture, threat model, runtime/network/GitHub boundaries, staged/CI scanning,
  release/SBOM flow, verification, and a compact limitations table. Corrected
  pre-existing overstatements about outside-bundle files and TLS ownership, and
  separated existing release guarantees from next-release SBOM readiness.
- 2026-08-26: Copilot identified three valid hook issues. Cleanup now uses an
  `EXIT` trap for errexit paths; the hook changes to the repository root; and
  staged/CI scans share Git/history/archive exclusions. Hook tests cover root
  anchoring, cleanup-trap policy, exact flags, missing binaries, and wrong
  versions.

## Surprises & Discoveries

- GitHub's default CodeQL setup runs all configured languages after every
  protected-branch push, including documentation-only follow-up commits. It is
  valuable security coverage but should not be duplicated by another scanner.
- Kingfisher's own CI guidance supports staged/current-tree scanning and
  provenance-verified release binaries, so no baseline is needed when published
  history is deliberately outside the blocking scope.
- GitHub advertises an attestation for the Kingfisher Linux digest, but the
  current GitHub CLI returns an opaque `promptError` while verifying it. The
  official verified tag plus GitHub-published asset SHA remains enforceable.

## Decision Log

- Keep CodeQL default setup and optimize the repository-owned jobs first; the
  largest avoidable cost is duplicate macOS startup, not the short Linux gates.
- Run Kingfisher inside the existing required Zizmor job to share checkout and
  runner startup instead of creating another billed job.
- Do not cache Kingfisher's rules or binary across untrusted pull requests.
- Generate the SBOM with the Python standard library from the authoritative
  lock rather than adding a package, container, or mutable generator.
- Use the existing pinned `actions/attest` action for the SBOM attestation; the
  older `actions/attest-sbom` wrapper is deprecated upstream.

## Outcomes & Retrospective

Pending implementation and verification.
