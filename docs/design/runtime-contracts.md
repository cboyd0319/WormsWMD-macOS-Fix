# Runtime Contracts

This document records the behavior agents should preserve when changing the
Worms W.M.D macOS fix.

## Primary Flow

`fix_worms_wmd.sh` is the canonical fix entrypoint. It detects or accepts a
`GAME_APP`, initializes logging, creates backups, runs the ordered fix scripts,
verifies the resulting bundle, and offers optional helper setup.

The ordered fix scripts are:

1. `scripts/01_build_agl_stub.sh` - build the AGL compatibility framework from
   `src/agl_stub.c`.
2. `scripts/02_replace_qt_frameworks.sh` - replace bundled Qt frameworks and
   plugins with Qt 5.15 assets.
3. `scripts/03_copy_dependencies.sh` - copy required dynamic libraries into the
   app bundle.
4. `scripts/04_fix_library_paths.sh` - rewrite install names to bundle-relative
   paths.
5. `scripts/05_verify_installation.sh` - verify framework, plugin, dependency,
   metadata, code-signing, and quarantine state.
6. `scripts/06_fix_info_plist.sh` - update bundle metadata and display flags.
7. `scripts/07_fix_config_urls.sh` - upgrade known HTTP URLs and disable
   internal/staging URLs.

Do not reorder these steps unless the verification contract is updated in the
same change.

## App Bundle Boundary

The fix may modify files inside the selected `Worms W.M.D.app` bundle and may
create user-owned backups, logs, cache files, and optional user LaunchAgents.
It must not modify system directories or require elevated privileges.

The default app path is:

```bash
$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app
```

`GAME_APP` may point elsewhere. Always quote it because the bundle path contains
spaces.

## Backup And Restore Contract

Before destructive bundle changes, the fix creates a timestamped backup under
`~/Documents/WormsWMD-Backup-*/`. Restore behavior must keep covering:

- `Contents/Frameworks/`
- `Contents/PlugIns/`
- `Contents/Info.plist` when backed up
- DataOSX config files when backed up

Save-game backup behavior belongs to `tools/backup_saves.sh` and must remain
separate from game-bundle restore behavior.

## Qt Distribution Contract

The preferred Qt source is the prebuilt archive in `dist/` plus its `.sha256`
file. Archive extraction must reject unsafe layouts and traversal paths.
Homebrew is a fallback, not the primary happy path.

When replacing the Qt archive:

- Update the matching checksum file.
- Validate the archive layout.
- Run the packaging or install verification relevant to the change.
- Update user docs if the version, source, or fallback behavior changes.

## Network Contract

Network access is limited to documented endpoints for repository downloads,
prebuilt Qt assets, update checks, preflight checks, and Apple-managed tool
installation prompts. Payloads that affect executable code must use HTTPS and
checksum verification.

The project does not collect telemetry.

## Logging And Diagnostics Contract

Fix logs are written under `~/Library/Logs/WormsWMD-Fix/` unless `LOG_FILE`
sets a user-writable file path. Debug tracing writes a `.trace` file next to the
selected log.

Launcher logs and crash reports are written under `~/Library/Logs/WormsWMD/`.
Diagnostics intended for bug reports should be collected with:

```bash
./tools/collect_diagnostics.sh
```

Diagnostics and reports must not expose secrets, private account data, or
unredacted sensitive config values.

## Validation Contract

For source-only changes, use the checks that match the blast radius:

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
```

For runtime changes on a macOS machine with Worms W.M.D installed, also run the
relevant dry-run, verify, preflight, launcher, or diagnostics workflow.
