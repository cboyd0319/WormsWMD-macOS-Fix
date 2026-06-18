# Cheat Sheet Supply-Chain Hardening

Status: Completed

## Problem

The issue-10 bug hunt fixed the immediate backup, diagnostics, and launcher
friction problems. The follow-up review against local security cheat sheets and
upstream Qt release information needs to catch any remaining security, pinning,
documentation, and user-friction gaps before v1.7.0 release prep starts.

## Scope and non-goals

- Review the local CheatSheetSeries guidance that applies to shell execution,
  logs/support bundles, file/archive handling, GitHub Actions, supply chain,
  dependency pinning, and dependency inventory.
- Verify current Qt 5.15.x availability from primary upstream sources and
  document what this repo can safely ship or consume.
- Enforce the supported Qt package series in scripts where a local or supplied
  Qt prefix is accepted.
- Update focused tests and documentation.
- Do not replace the `dist/` Qt archive in this pass.
- Do not begin v1.7.0 release prep in this pass.

## Constraints and risks

- The shipped Qt archive cannot be replaced without checksum, metadata, archive
  layout, manifest, and x86_64 validation.
- Qt 5.15.19 is available through Homebrew's current `qt@5` formula and Qt's
  archived open-source source package; this project must still pin and verify
  the x86_64 runtime bottle closure before shipping it.
- Support bundles and diagnostics must stay sanitized by default.
- Windows 11 and macOS 26+ repo behavior must remain intact.

## Milestones

- [x] Milestone 1: Review repo security docs, Qt packaging scripts, CI pins, and
  relevant local cheat-sheet guidance.
- [x] Milestone 2: Implement the smallest code guard for supported Qt 5.15.x
  package/prefix versions.
- [x] Milestone 3: Update docs and regression tests for Qt 5.15.x pinning,
  stale network endpoints, and validation commands.
- [x] Milestone 4: Run verification and record results.

## Verification

- `./tools/test_qt_version_pinning.sh` proves only Qt 5.15.x package names and
  local package inputs are accepted.
- `./tools/validate_harness.sh` proves docs topology and harness links remain
  valid.
- `shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh`
  checks shell safety after script edits.
- `for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done`
  checks shell syntax.
- `./fix_worms_wmd.sh --verify`, `./tools/preflight_check.sh --quick`, and
  `./tools/collect_diagnostics.sh --bundle --output /tmp/wormswmd-support-check`
  confirm local fixed-install, preflight, and support-bundle behavior.

## Progress

- 2026-06-18: Confirmed the repo still had a stale `SECURITY.md` network row
  after the Team17/Steam preflight URL fix.
- 2026-06-18: Confirmed release and install paths use checksum/commit/action
  pins, while local Qt prefix packaging needed an explicit supported-version
  guard.
- 2026-06-18: Added a shared Qt 5.15.x version guard, applied it to package
  discovery, maintainer packaging, and Homebrew fallback detection, and added a
  regression test.
- 2026-06-18: Added maintainer packager support for an isolated dependency
  prefix so a verified x86_64 Homebrew bottle closure can be packaged without
  requiring permanent Intel Homebrew installation under `/usr/local`.
- 2026-06-18: Rebuilt `dist/` with Qt 5.15.19 from a locked 17-entry Homebrew
  x86_64 bottle closure, embedded `SOURCE_PROVENANCE.tsv`, and validated the
  committed archive with `scripts/download_qt_frameworks.sh`.

## Surprises & Discoveries

- Qt 5.15.19 is the final upstream Qt 5.15 release. Homebrew exposes `qt@5`
  stable 5.15.19 from Qt's archived open-source source package and publishes a
  Sonoma x86_64 bottle that can be fetched by GHCR blob digest.

## Decision Log

- Ship the 5.15.19 `dist/` artifact because it was rebuilt from the locked
  x86_64 Homebrew bottle closure and passed checksum, layout, manifest, and
  Mach-O validation.
- Reject non-5.15.x Qt package names and packaging inputs instead of attempting
  best-effort compatibility with other Qt 5 releases.
- Prefer temporary, verified bottle extraction for the 5.15.19 packaging
  attempt before asking for a system-wide Intel Homebrew install.

## Outcomes & Retrospective

Shipped a Qt 5.15.19 runtime archive with checksum and source provenance, plus
the maintainer helper needed to rebuild the isolated bottle prefix from the
lock.

Verification completed on macOS 26.5.1:

- Harness, shell syntax, Ruby syntax, ShellCheck, and all focused regression
  scripts passed.
- `scripts/download_qt_frameworks.sh --check` accepted the 5.15.19 archive, and
  `shasum -a 256 -c` verified its checksum.
- A full release zip smoke build included the 5.15.19 archive, checksum, and
  source-provenance lock.
- The live Steam game was restored to original Qt 5.3.2, then fixed from that
  state with the new pre-built Qt 5.15.19 archive.
- `fix_worms_wmd.sh --verify`, full `tools/preflight_check.sh`, support-bundle
  privacy scan, and bounded launch smoke passed after applying the fix.
