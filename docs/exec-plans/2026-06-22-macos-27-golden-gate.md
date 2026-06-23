# macOS 27 Golden Gate Compatibility

Status: Active

## Problem

macOS 27 Golden Gate changes the Intel translation story for Apple Silicon
users. Local validation showed that after upgrading to macOS 27.0 build
26A5368g, Rosetta was not restored automatically, `arch -x86_64` failed, and
`game-test-tool` existed but was disabled. Installing Rosetta manually restored
x86_64 execution and allowed a Worms W.M.D launch smoke to start through Steam.

The repository has an unpublished local release-prep commit on `main` that
bundles the macOS 27 code, tests, diagnostics, docs, and v1.7.2 release
surfaces. The release still must not be pushed, tagged, or published until the
final release gate is explicitly completed.

## Scope and non-goals

In scope:

- Installer and bootstrap entrypoints: `install.sh`, `Install Fix.command`.
- Friendly launcher flow: `Worms W.M.D Fix.command`.
- Core fix engine: `fix_worms_wmd.sh`.
- Runtime checks and diagnostics: `tools/preflight_check.sh`,
  `tools/collect_diagnostics.sh`, `tools/launch_worms.sh`.
- Regression tests and validation harnesses under `tools/`.
- User-facing docs: `README.md`, `README_FIRST.txt`, `docs/INSTALL.md`,
  `docs/TROUBLESHOOTING.md`, `docs/FAQ.md`, `docs/IMPROVEMENTS.md`,
  `docs/TECHNICAL.md`, `docs/TOOLS.md`, `docs/TRUST.md`,
  `TEAM17_DEVELOPER_REPORT.md`, release notes, and changelog.
- Release packaging and bootstrap pinning for a future version.

Out of scope:

- Rebuilding or modifying official Worms W.M.D game binaries.
- Replacing Team17, Steam, GOG, FMOD, or Steamworks dependencies.
- Automatically enabling `game-test-tool`, changing boot args, using `sudo`, or
  making other system-wide beta toggles.
- Claiming macOS 28 support before Apple finalizes the legacy game behavior.

## Constraints and risks

- Do not push, tag, or publish the current macOS 27 WIP until this plan is
  completed.
- Do not add `sudo`, system-wide writes, SUID bits, privileged persistence, or
  automatic `game-test-tool enable`.
- Preserve user game data and save data.
- Keep downloads HTTPS-only and checksum-verified for executable payloads.
- Treat `GAME_APP`, `INSTALL_DIR`, `INSTALL_REF`, `LOG_FILE`, and `QT_PREFIX`
  as untrusted input.
- Preserve macOS 26+ behavior while adding macOS 27 guidance.
- Preserve Windows 11 repository inspection behavior for shell syntax,
  harness, and documentation checks.
- Apple beta behavior is volatile. Use local observed behavior and official
  Apple docs as evidence, and phrase docs as Golden Gate beta guidance where
  appropriate.

## Milestones

- [x] Milestone 1: Define macOS 27 release gate.
  - Record local evidence from macOS 27.0 build 26A5368g.
  - Record official Apple source evidence for Rosetta through macOS 27 and
    legacy game support.
  - Decide exact wording for "supported", "validated", and "known limits".

- [x] Milestone 2: Audit all user entrypoints.
  - Inspect `install.sh`, `Install Fix.command`, `Worms W.M.D Fix.command`,
    `fix_worms_wmd.sh`, and `tools/launch_worms.sh`.
  - Remove Tahoe-only wording where the behavior is macOS 26+.
  - Ensure option 3 in the friendly launcher checks launch readiness, not only
    bundle verification.
  - Ensure post-fix flow runs preflight before suggesting launch.

- [x] Milestone 3: Harden Rosetta and Intel translation checks.
  - Verify `ensure_rosetta()` runs `/usr/bin/arch -x86_64 /usr/bin/true` after
    `softwareupdate --install-rosetta --agree-to-license`.
  - On macOS 27 failure, report `game-test-tool status` when available without
    enabling it.
  - Keep dry-run non-mutating and non-fatal for missing translation.
  - Preserve macOS 26 missing-Rosetta behavior.

- [x] Milestone 4: Expand diagnostics and support bundles.
  - Add Rosetta receipt status.
  - Add x86_64 execution probe result.
  - Add `oahd` running/not-running status.
  - Add `game-test-tool status` when available.
  - Ensure support bundle output remains sanitized.

- [x] Milestone 5: Add regression coverage.
  - Add stubs or focused tests for macOS 27 with Rosetta absent.
  - Add tests for macOS 27 with Rosetta present.
  - Add tests for macOS 26 with Rosetta absent.
  - Keep Bash 3.2 compatibility.

- [x] Milestone 6: Update docs and release materials.
  - Update all stale Tahoe-only text.
  - Add `README_FIRST.txt` macOS 27 guidance.
  - Update changelog and version references only when release-ready.
  - Do not update bootstrap pins until the final release commit exists.

- [x] Milestone 7: Run release-grade verification.
  - Run the full repository validation contract.
  - Run real macOS 27 checks on this laptop:
    `sw_vers`, Rosetta receipt, x86_64 probe, `game-test-tool status`,
    `./tools/preflight_check.sh --quick`, `./fix_worms_wmd.sh --verify`,
    `./tools/collect_diagnostics.sh`, and a bounded launch smoke.
  - Confirm no Worms process remains after launch smoke.
  - Run release bundle smoke before any release commit.

## Verification

Focused checks:

```bash
./tools/test_preflight_regression.sh
./tools/test_issue_11_game_detection.sh
./tools/test_support_bundle_sanitization.sh
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
```

Full validation contract:

```bash
./tools/validate_harness.sh
./tools/test_dependency_parsing.sh
./tools/test_issue_10_regression.sh
./tools/test_issue_11_game_detection.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_backup_saves_regression.sh
./tools/test_launcher_friction.sh
./tools/test_preflight_regression.sh
./tools/test_manifest_regression.sh
./tools/test_qt_version_pinning.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
./scripts/download_qt_frameworks.sh --check
./tools/package_qt_frameworks.sh --help
./tools/collect_diagnostics.sh --help
./tools/backup_saves.sh --help
./tools/build_release_bundle.sh --version local-smoke --skip-zip
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
```

macOS 27 live checks:

```bash
sw_vers
pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto
/usr/bin/arch -x86_64 /usr/bin/true
/usr/bin/arch -x86_64 /usr/bin/uname -m
game-test-tool status
./tools/preflight_check.sh --quick
./fix_worms_wmd.sh --verify
./tools/collect_diagnostics.sh
```

## Progress

- 2026-06-22: Created this plan after local macOS 27 validation and user
  clarified that no macOS 27 fix should be pushed until the entire repo is
  fully fixed for Golden Gate.
- 2026-06-22: Early local WIP commit `d1c98f3` existed on `main` and was not
  pushed by itself.
- 2026-06-22: Added red/green regression coverage for launcher readiness,
  bootstrap wording, Rosetta post-install verification, and diagnostics
  translation probes.
- 2026-06-22: Updated `Worms W.M.D Fix.command` so option 3 runs both quick
  preflight and bundle verification, and post-apply launch is offered only
  after readiness passes.
- 2026-06-22: Updated Rosetta user-facing copy to say plainly that Worms W.M.D
  is an older Intel Mac game, Rosetta is required on Apple Silicon, and the
  command to install it is `softwareupdate --install-rosetta --agree-to-license`.
- 2026-06-22: Expanded diagnostics to include Rosetta package receipt, `oahd`,
  x86_64 execution probe, and `game-test-tool status` for support context.
- 2026-06-22: Added Rosetta package version to diagnostics and verified a live
  support bundle contains macOS `27.0 (26A5368g)` and Rosetta package version
  `1.0.0.0.1781856704`.
- 2026-06-22: Full validation contract passed after launcher, diagnostics,
  docs, and tests were updated.
- 2026-06-22: Live Golden Gate checks passed: Rosetta receipt, x86_64 probe,
  `game-test-tool status`, preflight, `--verify`, friendly launcher option 3,
  support bundle extraction, and bounded launch smoke with no Worms process
  left running.
- 2026-06-22: User captured a local screenshot showing Worms W.M.D running
  with macOS Golden Gate 27.0 Beta build 26A5368g visible. Treat as local
  validation evidence only; do not commit or bundle the image because it
  contains official Worms W.M.D artwork.
- 2026-06-22: Added a harness guard so tracked and unignored text files fail
  validation if they contain accidental local machine paths from maintainer
  workstations.
- 2026-06-22: Verified the local-path guard with a failing temporary fixture,
  then reran the full repository validation contract successfully after the
  guard and documentation updates.
- 2026-06-22: Verified Apple's Rosetta support article dated 2026-02-23
  (`https://support.apple.com/102527`). It says Rosetta remains available
  through macOS 27 and that macOS 28 narrows Rosetta functionality to certain
  older, unmaintained games that rely on Intel frameworks.
- 2026-06-22: Prepared deterministic v1.7.2 release surfaces locally:
  `fix_worms_wmd.sh` version, release examples, bootstrap default refs, issue
  template placeholder, changelog, and player docs. Bootstrap exact commit pins
  are intentionally empty for the future release tag commit.
- 2026-06-22: Re-audited all tracked Markdown, text, and issue-template docs
  after maintainer feedback. Updated the main README, security docs, support
  docs, issue templates, Team17 report, runtime contracts, and tool docs so
  macOS 27, Rosetta, support-bundle, launch-readiness, and v1.7.2 guidance are
  consistent.
- 2026-06-22: Full validation contract passed again after the docs audit and
  v1.7.2 release-surface updates. Built the v1.7.2 release zip, verified its
  checksum, and read back the bundled README, README_FIRST, and SUPPORT files
  to confirm the updated macOS 27 and Rosetta guidance is in the release
  artifact.
- 2026-06-22: Squashed the unpublished local stack into one release-prep commit
  on `main`; preserved the prior five-commit stack on local branch
  `backup/macos27-v172-stack-20260622`.

## Surprises & Discoveries

- macOS 27.0 build 26A5368g did not restore Rosetta automatically after upgrade.
- `softwareupdate --install-rosetta --agree-to-license` still succeeded on the
  local Golden Gate beta and restored x86_64 execution.
- `game-test-tool` is present on macOS 27 beta, but local status remained
  disabled/inactive after Rosetta install.
- Directly launching the game executable exited cleanly after handing off to
  Steam, and Steam then spawned the actual Worms process.
- User feedback clarified that wording such as "Intel app translation" and
  "legacy game guidance" is too technical for most players; user-facing output
  should name Rosetta, explain why it is needed, and show the exact command.
- The support bundle needs both OS version and Rosetta version because users are
  instructed to upload it to GitHub issues.
- Screenshot proof is useful for maintainer validation, but screenshots of the
  running game contain official game artwork and should not be added to tracked
  repo assets without license and attribution approval.

## Decision Log

- Do not enable `game-test-tool` automatically. It is beta-only, requires
  privileged system changes, and should remain a user/developer decision.
- Treat macOS 27 support as "validated with Rosetta installed" for Apple
  Silicon.
- Keep dry-run non-mutating. Missing Intel translation should be reported as a
  warning in preview mode, not as a hard preview failure.
- User-facing Rosetta failures should avoid platform jargon. Prefer:
  "Worms W.M.D is an older Intel Mac game. Install Rosetta, then run option 3
  again."
- Do not update release pins, changelog release headings, or publishable version
  references until a release commit is intentionally prepared.
- Prefer command output, support bundles, and written validation notes as
  release evidence. Keep game screenshots out of the release bundle unless the
  asset policy is satisfied.
- Convert avoidable release-hygiene mistakes into validation checks when the
  condition can be detected locally.
- The release tag commit should keep bootstrap exact commit pins empty, matching
  the v1.7.0/v1.7.1 release pattern. The next mainline commit after the tag
  should pin installers to the exact v1.7.2 tag target.

## Outcomes & Retrospective

Pending.
