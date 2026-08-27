# Security Remediation PR 2: Archive And Bottle Safety

Status: Completed

## Problem

Archive consumers lack consistent compressed/expanded/member/type limits. The
maintainer bottle tool accepts weak lock and URL input, forwards authorization
through redirects, executes extracted `qmake`, and recursively deletes arbitrary
output.

## Scope and non-goals

In scope: a standard-library Python 3.9 archive inspector, integration at every
archive read/extraction boundary, strict bottle lock/download/extraction rules,
nonexecuting Qt version validation, marker-owned staged output, an authoritative
packaging lock, and one-formula refresh support.

Out of scope: save destination replacement, Qt cache identity, Homebrew runtime
dependency copying, changing `dist` bytes, GitHub settings, and release
publication.

## Constraints and risks

- Python 3.9+ standard library only; no pip, packages, or auto-install.
- Mutating/extracting paths fail before mutation without Python; help/list/
  location and sanitized diagnostics remain usable.
- Inspect and extract the same owner-only temporary copy; re-hash it against an
  external digest when present.
- No unlimited archive/output override and no local artifact replacement.
- Run the current real lock smoke once locally only after network-free green.

## Milestones

- [x] Add red archive-inspector tests and implement bounded Python 3.9 parsing.
- [x] Integrate all archive consumers, CI, contracts, docs, and compatibility.
- [x] Add red bottle tests and harden lock/download/extraction/output/refresh.
- [x] Run one real-lock smoke and local/adversarial full verification.
- [x] Commit, open one PR, request one Copilot review, verify CI, and merge.
- [x] Complete plans and record exact PR 3 base.

## Verification

```bash
/usr/bin/python3 tools/test_archive_inspector.py -v
ruby -c tools/fetch_qt_homebrew_bottles.rb
ruby tools/test_fetch_qt_homebrew_bottles.rb
/usr/bin/python3 tools/test_generate_sbom.py
./tools/test_qt_version_pinning.sh
./tools/test_backup_saves_regression.sh
./tools/test_git_hooks.sh
./tools/test_support_bundle_sanitization.sh
shellcheck fix_worms_wmd.sh scripts/common.sh scripts/download_qt_frameworks.sh tools/backup_saves.sh tools/install_git_hooks.sh tools/collect_diagnostics.sh tools/package_qt_frameworks.sh
for script in fix_worms_wmd.sh scripts/common.sh scripts/download_qt_frameworks.sh tools/backup_saves.sh tools/install_git_hooks.sh tools/collect_diagnostics.sh tools/package_qt_frameworks.sh; do bash -n "$script"; done
git diff --check
git status --short
```

## Progress

- 2026-08-27: Branch `security/pr2-archive-bottle-safety` created at
  `01034eb0bbf07a0d7833f58dd8093a189e0cd78f`. Existing Qt, save, hook,
  support-bundle, SBOM, Ruby syntax, Qt availability, help, and harness checks
  passed. Apple CLT Python is 3.9.6.
- 2026-08-27: Network-free archive, SBOM, Qt, save, hook, diagnostics,
  launcher, bottle, CI-policy, harness, syntax, and ShellCheck gates passed.
- 2026-08-27: One real-lock smoke completed from the same cache after the
  inspector rejected two inaccurate initial assumptions. Observed redirect was
  `ghcr.io` HTTP 307 to `pkg-containers.githubusercontent.com`; all 17 bottle
  digests and embedded metadata validated, revisioned Cellar roots were bound
  to their formula metadata, 1,822 Mach-O references were relocated, QtCore was
  `x86_64`, and the marker-owned staged prefix published successfully. The 415
  MiB smoke workspace was moved to Trash.
- 2026-08-27: [PR #26](https://github.com/cboyd0319/WormsWMD-macOS-Fix/pull/26)
  received one automatic Copilot review. Both findings were fixed in `6683040`,
  replied to, and resolved. GitHub Security run 14 and CI run 113 passed at the
  exact reviewed head, including the full macOS job.
- 2026-08-27: PR #26 merged to protected `main` as
  `671f1285b69fd4a1597044521525b61f39d5ee13`. PR 3 must start from the latest
  protected `main`, including this closeout record.

## Surprises & Discoveries

- The locked Qt 5.15.19 bottle has 11,886 members, above the planned 10,000
  initial bottle-profile limit. The bounded profile was raised to 16,384 after
  measuring the verified locked blob; all other bottle limits remain unchanged.
- Direct Homebrew bottle archives do not contain `INSTALL_RECEIPT.json`; Homebrew
  creates that file while pouring a bottle. The fetcher instead validates the
  digest-pinned exact formula/version root plus bounded `.brew/FORMULA.rb`
  metadata containing the lock's source checksum, without executing Ruby.
- Homebrew lock `version` values are stable source versions, while a bottle may
  use a revisioned Cellar root such as `4.7.1_1`. Revisioned roots are accepted
  only when their base equals the lock and bounded embedded formula metadata
  contains the exact nonzero `revision N`; `opt` links use that validated root.

## Decision Log

- One Python inspector owns archive resource/type/path policy. Shell and Ruby
  consumers remain thin callers and add only their domain-specific schema.
- Diagnostics degrade safely instead of making Python a prerequisite for support.
- The bottle member limit is 16,384 because the current digest-pinned Qt bottle
  contains 11,886 members; the planned 10,000 limit was incompatible.
- Direct bottles are validated through digest, exact version/revision root,
  source checksum in bounded embedded formula metadata, and QtCore architecture.
  They do not claim an `INSTALL_RECEIPT.json` that direct bottles do not contain.

## Outcomes & Retrospective

Completed in PR #26. The implementation adds bounded same-copy archive
inspection, safe Python degradation, a reviewed bottle lock, nonexecuting
formula validation, restricted redirects, and marker-owned staged output. All
local and hosted gates passed; `dist` bytes and user saves were unchanged.

Residual player/runtime findings are handed to PR 3: the fixed Steam app's
plugin self-install IDs are false positives in dependency verification, and a
separate `/Applications` installation remains unfixed. PR 3 starts from
the latest protected `main`, including this closeout record.
