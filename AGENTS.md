# Agent Instructions

This file is the short repo map for coding agents. Keep durable detail in the
linked docs and update this map only when entrypoints, commands, or hard rules
change.

## Project Shape

- `fix_worms_wmd.sh` is the primary installer/fix orchestrator.
- `Worms W.M.D Fix.command` is the friendly double-click menu wrapper.
- `install.sh` is the curl-pipe bootstrapper that clones or updates this repo.
- `Install Fix.command` is the tiny double-click bootstrapper that downloads or
  updates the repo and opens the friendly launcher.
- `scripts/` contains fix steps and shared shell helpers.
- `tools/` contains diagnostics, backups, launch helpers, packaging, update
  checks, and harness validation.
- `src/agl_stub.c` is the AGL compatibility stub source.
- `dist/` contains the prebuilt Qt framework archive and checksum.
- `docs/README.md` is the durable documentation index.

## Non-Negotiables

- Do not add `sudo`, system-wide writes, SUID bits, or privileged persistence.
- Preserve user game data and save data. Any destructive game-bundle change must
  keep the existing backup and restore story intact.
- Keep downloads HTTPS-only and checksum-verified when the payload is executable
  code, frameworks, libraries, or archives.
- Treat `GAME_APP`, `INSTALL_DIR`, `INSTALL_REF`, `LOG_FILE`, and `QT_PREFIX`
  as untrusted user input. Quote paths and preserve spaces in
  `Worms W.M.D.app`.
- Update code, tests/checks, docs, and runbooks together when behavior changes.
- Do not publish secrets from game config files, logs, diagnostics, or reports.
- Do not replace the Qt archive in `dist/` without updating its checksum and
  validating extraction layout.
- Do not bundle official Team17/Worms art or third-party sample assets without
  committed license and attribution evidence.

## Startup Path

1. Run `git status --short --branch`.
2. Read this file, `docs/README.md`, and
   `docs/design/runtime-contracts.md`.
3. Check `docs/exec-plans/` for active work before editing.
4. For multi-step changes, create or update an execution plan from
   `docs/exec-plans/TEMPLATE.md`.

## Common Commands

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
./tools/build_release_bundle.sh --version local-smoke --skip-zip
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
```

Run `./fix_worms_wmd.sh --verify`, `./tools/preflight_check.sh`, and
`./tools/collect_diagnostics.sh` on macOS when a real Worms W.M.D installation
is available.

## Documentation Entrypoints

- `docs/README.md` - full tracked documentation index.
- `docs/design/runtime-contracts.md` - architecture, data, network, and runtime
  invariants.
- `docs/runbooks/agent-session.md` - startup, validation, diagnostics, handoff,
  and clean-state workflow.
- `docs/style/agent-harness.md` - harness engineering rules for this repo.
- `docs/exec-plans/README.md` - plan lifecycle and required sections.
- `SECURITY.md` - threat model and security validation expectations.
- `CONTRIBUTING.md` - contributor workflow and PR expectations.

## Completion Checklist

- Relevant execution plan status is updated, if a plan exists.
- User-facing docs match behavior and command names.
- `./tools/validate_harness.sh` passes after harness or Markdown changes.
- Shell scripts pass `bash -n`; run ShellCheck when shell code changes.
- `git status --short` shows only intentional changes before handoff.
