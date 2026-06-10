# Deep Repository Audit

Status: Completed

## Problem

The repository needs a broad defect pass across installer scripts, helper tools,
documentation contracts, and validation harnesses. The goal is to find concrete
bugs or mismatches that can break player workflows, maintainer releases, or
documented validation, then fix them in this session.

## Scope and non-goals

In scope:

- Root launchers: `fix_worms_wmd.sh`, `install.sh`,
  `Install Fix.command`, and `Worms W.M.D Fix.command`.
- Ordered fix scripts under `scripts/`.
- Helper tools under `tools/`.
- Documentation and harness files when behavior or validation changes.
- Static checks, dry-run flows, and release bundle smoke checks that can run
  without a real Worms W.M.D installation.

Non-goals:

- No replacement of `dist/` Qt archives.
- No privileged operations, system-wide writes, or real game-bundle mutation
  without explicit user direction.
- No live Steam/GOG game validation unless a local install is available and the
  relevant command is safe.

## Constraints and risks

- Preserve backups, save data, and restore behavior.
- Keep downloads HTTPS-only and checksum-verified for executable payloads.
- Treat `GAME_APP`, `INSTALL_DIR`, `INSTALL_REF`, `LOG_FILE`, and `QT_PREFIX`
  as untrusted input.
- Preserve macOS 26+ player behavior and avoid breaking Windows 11 repository
  inspection or release-bundle workflows.
- Avoid broad rewrites; patch only observed defects or clear contract drift.

## Milestones

- [x] Baseline: run harness, syntax, ShellCheck if available, dry-run/help,
  package helper smoke checks, and release bundle smoke check.
- [x] Static audit: inspect shell entrypoints and risky patterns around file
  deletion, archive extraction, network downloads, temp dirs, path quoting,
  secret redaction, and docs contract drift.
- [x] Implement: patch concrete defects with focused changes, preserving local
  style.
- [x] Docs/harness: update docs or validation when behavior changes.
- [x] Verify: rerun the smallest relevant checks plus broader gates touched by
  the fixes.

## Verification

Target commands:

```bash
./tools/validate_harness.sh
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

Runtime-only checks, if safe and relevant:

```bash
./tools/preflight_check.sh --quick
./fix_worms_wmd.sh --verify
```

## Progress

- 2026-06-10: Created plan after startup docs and historical execution plans
  showed no active work.
- 2026-06-10: Baseline checks found ShellCheck, Bash syntax, help, dry-run, Qt
  package check, release bundle smoke, and AGL compile passing. Harness failed
  only because this new plan was not yet linked from `docs/README.md`.
- 2026-06-10: Patched verification failure handling, CommonData backup/restore,
  Info.plist idempotence, bootstrap installer destination safety, config URL
  backup behavior, and matching docs.
- 2026-06-10: Final validation passed except runtime preflight against a real
  default game install, which failed because no Worms W.M.D app exists at the
  default local path.

## Surprises & Discoveries

- `fix_worms_wmd.sh` disabled rollback before running the final verifier and
  still printed success after verifier errors.
- `scripts/07_fix_config_urls.sh` changed `CommonData` configs, but main backup
  and restore only covered `DataOSX`.
- `scripts/06_fix_info_plist.sh` added missing keys but did not correct existing
  false values and could fail when `LSMinimumSystemVersion` was absent.
- Bootstrap installers could move aside arbitrary existing directories or Git
  repositories if `INSTALL_DIR` or `~/.wormswmd-fix` pointed somewhere unsafe.
- Config URL fixes created `.backup` files beside game configs, preserving the
  original HTTP and internal URL values inside the app bundle.
- Runtime and manual install docs listed verifier order before metadata and URL
  fixes, while the engine verifies after those changes.

## Decision Log

- Use local source and validation output as current evidence; prior memory
  search did not return relevant facts for this repository.
- Treat verifier errors as installer failure and keep rollback enabled until the
  verifier returns success.
- Refuse unknown non-empty installer destinations instead of moving them aside;
  preserving user data is more important than automatic recovery from an
  unexpected directory shape.
- Stop creating in-bundle config `.backup` files because the main installer now
  backs up both edited config directories with a manifest.

## Outcomes & Retrospective

Completed with focused fixes in installer, restore, verification, config, and
documentation paths.

Validation passed:

```bash
./tools/validate_harness.sh
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
git diff --check
```

Focused smoke checks passed for:

- Info.plist correction on a fake app bundle.
- Manifest-backed restore of `CommonData` on a fake app bundle.
- Config URL rewriting without creating new `.backup` files.
- `install.sh` refusal for non-empty non-checkout directories and wrong Git
  remotes.
- Support bundle creation to a temporary output directory.

Runtime caveat:

```bash
./tools/preflight_check.sh --quick
```

This failed because the default local game path does not exist on this machine:
`~/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app`.
