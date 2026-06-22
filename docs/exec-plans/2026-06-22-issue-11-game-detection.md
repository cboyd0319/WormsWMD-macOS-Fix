# Issue 11 Game Detection

Status: Completed

## Problem

Issue #11 reports a release-zip launcher failure on macOS 26.5.1 with a GOG
copy of Worms W.M.D. The installer crashes during game discovery with
`unique_games[@]: unbound variable` before it can find or reject the game path.

## Scope and non-goals

Fix `fix_worms_wmd.sh` auto-detection for Bash 3.2 strict mode, cover GOG
discovery in focused regression checks, audit the attached support bundle for
adjacent gaps, update all affected docs, and prepare a v1.7.1 patch release if
validation passes. Do not change Qt packaging, backup behavior, or game-bundle
mutation behavior beyond discovery and reporting.

## Constraints and risks

The fix must keep macOS `/bin/bash` 3.2 compatibility, preserve paths with
spaces, avoid privileged operations, and keep Steam discovery behavior intact.
The local machine does not have a real Worms W.M.D install, so verification uses
isolated fake app bundles.

## Milestones

- [x] Milestone 1: Inspect issue #11, discovery code, and validation wiring.
- [x] Milestone 2: Add a failing regression check for empty, GOG, and duplicate
  discovery.
- [x] Milestone 3: Implement the smallest Bash 3.2-compatible fix.
- [x] Milestone 4: Update docs/check wiring and run focused validation.
- [x] Milestone 5: Deep-audit the issue #11 support bundle for other likely
  user-facing gaps.
- [x] Milestone 6: Verify Steam/GOG/macOS path assumptions with current
  research and update discovery/docs if needed.
- [x] Milestone 7: Sweep all docs and release metadata for v1.7.1 readiness.
- [x] Milestone 8: Run release-grade validation and decide whether to cut
  v1.7.1.

## Verification

- `./tools/test_issue_11_game_detection.sh` proves game discovery no longer
  crashes under Bash 3.2 strict mode and finds a GOG-style app path.
- `bash -n fix_worms_wmd.sh tools/test_issue_11_game_detection.sh` proves edited
  shell syntax parses.
- `./tools/validate_harness.sh` proves docs and harness links stay consistent.
- Focused existing checks prove adjacent launcher and script behavior remains
  intact.

## Progress

- 2026-06-22: Confirmed issue #11 report and reproduced the empty-array
  strict-mode failure on local `/bin/bash` 3.2.57.
- 2026-06-22: Added `tools/test_issue_11_game_detection.sh`; verified it failed
  red against the current code with an empty discovery result.
- 2026-06-22: Moved game discovery into `scripts/common.sh`, updated installer,
  diagnostics, and preflight callers, and wired the regression check into CI
  and maintainer command lists.
- 2026-06-22: Ran focused verification successfully.
- 2026-06-22: Reopened the plan after user requested a deeper support-bundle
  audit, path research, docs sweep, and v1.7.1 release consideration.
- 2026-06-22: Audited the issue #11 support bundle. The bundle showed macOS
  26.5.1 on Apple Silicon, no detected default Steam install, no backup
  manifests, and a verified bundled Qt package. The installer had crashed
  before game-bundle or backup work, so no rollback evidence was expected.
- 2026-06-22: Found that the support-bundle tar stream leaked local owner/group
  names in archive listings even though report contents were sanitized; updated
  bundle creation and regression coverage to normalize archive metadata.
- 2026-06-22: Confirmed public Team17, Steam, and GOG Worms W.M.D pages are the
  appropriate optional preflight reachability probes. The checks remain
  diagnostic only and do not prove multiplayer, store auth, or backend health.
- 2026-06-22: Extended GOG-aware discovery to diagnostics, preflight, the
  friendly launch option, the enhanced launcher, and watcher status checks.
- 2026-06-22: Updated v1.7.1 release metadata, changelog, README, install,
  trust, security, troubleshooting, FAQ, tools, and runtime-contract docs.
- 2026-06-22: Ran release-grade validation and built a local v1.7.1 release
  zip with a verified checksum.

## Surprises & Discoveries

GOG is relevant to coverage, but the immediate crash is not GOG-specific. Any
empty or first-match discovery path can trip the same Bash 3.2 `set -u` array
expansion behavior.

GOG's current support page identifies `$HOME/GOG Games` as the default install
directory. The repo also already had a legacy
`~/Library/Application Support/GOG.com/Games/...` path, so the regression keeps
both covered.

The official GOG product page for Worms W.M.D is reachable at
`https://www.gog.com/en/game/worms_wmd`, so GOG belongs in the optional public
preflight endpoint set alongside the Team17 and Steam product pages.

Support-bundle body redaction is not enough by itself; archive metadata can
also leak the local macOS account and group through `tar -tvzf` listings.

## Decision Log

Use a direct regression script instead of a new test framework. The repo already
uses small shell regression scripts, and this bug is shell/runtime-specific.

Share discovery through `scripts/common.sh` rather than keeping separate
Steam/GOG path lists in the installer, diagnostics, and preflight scripts.

Use public product pages for preflight reachability checks. Avoid private or
service-style endpoints because they are more likely to be noisy, deprecated,
or unrelated to whether this local compatibility fix can run.

Prepare v1.7.1 locally but do not create or push a release tag without explicit
maintainer approval. The release-tag bootstrap cannot contain its own final
commit hash; mainline can pin the exact tag target in the follow-up commit after
the tag exists.

## Outcomes & Retrospective

Issue #11 is fixed and covered. GOG-aware game discovery is shared by the
installer, diagnostics, preflight, friendly launch option, enhanced launcher,
and watcher status check. Support bundles no longer expose local owner/group
metadata through tar listings. Documentation and release metadata are prepared
for v1.7.1. A local v1.7.1 release zip builds and verifies, but no tag or
GitHub release has been published from this plan.
