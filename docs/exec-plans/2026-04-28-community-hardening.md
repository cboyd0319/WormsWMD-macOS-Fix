# Community Hardening: Qt Packages, Diagnostics, and Restore Safety

Status: Completed

## Objective

Make the project easier for the community to trust without requiring frequent maintainer involvement. This pass implements the selected improvements:

- Qt 5.15.19-compatible artifact path without claiming a public open-source artifact that is not available in this repo.
- Stronger verification for prebuilt Qt archives before they are advertised or extracted.
- Reproducible, configurable Qt package creation for future artifact refreshes.
- Sanitized diagnostics support bundle generation for easier issue reporting.
- Backup manifests and restore verification for both game repair backups and save-game backup archives.

## Scope

Expected files:

- `scripts/common.sh`
- `scripts/download_qt_frameworks.sh`
- `tools/package_qt_frameworks.sh`
- `tools/collect_diagnostics.sh`
- `tools/backup_saves.sh`
- `fix_worms_wmd.sh`
- Documentation under `docs/`, `README.md`, `SECURITY.md`, and `CHANGELOG.md`

## Non-Goals

- Do not add a Qt 5.15.19 binary artifact unless one is locally supplied and can be verified.
- Do not replace the installer UX or rewrite the repair flow.
- Do not add network update checks or release automation in this pass.
- Do not change game assets or runtime behavior beyond safer install/restore validation.

## Plan

1. Add shared helpers for semantic Qt package selection and manifest generation/verification where useful.
2. Teach Qt download checks to validate local archive checksums, tar layout, metadata, required contents, and x86_64 Mach-O slices before reporting a package as available.
3. Update Qt package creation to accept an explicit Qt prefix/version, generate deterministic archives, and emit package manifests.
4. Add a sanitized support bundle mode to diagnostics collection.
5. Add backup manifests during fix backup creation, verify manifests before restore/rollback, and validate save-game backup archives before extraction.
6. Refresh all docs affected by the new operational contract.
7. Run the repo validation commands and record results.

## Validation

Run:

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
./scripts/download_qt_frameworks.sh --check
./tools/package_qt_frameworks.sh --help
./tools/collect_diagnostics.sh --help
./tools/backup_saves.sh --help
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
```

If a support bundle is generated during testing, inspect the archive listing and remove the generated bundle before commit.

## Completion Notes

Completed the hardening pass with:

- Highest-version verified Qt package selection and full local archive
  validation before `--check` reports availability.
- Deterministic Qt package creation with explicit `--qt-prefix`, `--version`,
  `SOURCE_DATE_EPOCH`, metadata, and `MANIFEST.txt`.
- Sanitized diagnostics support bundles with Qt package verification details
  and backup manifest collection.
- Game-bundle backup manifests plus restore/rollback verification.
- Save-game archive manifests, archive layout validation, and post-restore
  verification.
- Updated user docs, maintainer docs, runtime contracts, security notes, and
  changelog.

Validation completed:

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
git diff --check
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
./scripts/download_qt_frameworks.sh --check
./tools/package_qt_frameworks.sh --help
./tools/collect_diagnostics.sh --help
./tools/backup_saves.sh --help
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
```

Additional smoke checks covered the shared manifest helpers, the reproducible
tar options, and `./tools/collect_diagnostics.sh --bundle --bundle-output /tmp`.
The generated support bundle contained only `README.txt`, `diagnostics.txt`,
`qt-package.txt`, and `backup-manifests/`, then it was removed from `/tmp`.
