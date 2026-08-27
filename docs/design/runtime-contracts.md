# Runtime Contracts

This document records the behavior agents should preserve when changing the
Worms W.M.D macOS fix.

## Primary Flow

`fix_worms_wmd.sh` is the canonical fix entrypoint. It detects or accepts a
`GAME_APP`, initializes logging, creates backups, runs the ordered fix scripts,
verifies the resulting bundle, and offers optional helper setup.

`Worms W.M.D Fix.command` is the friendly double-click launcher. It must remain
a wrapper around `fix_worms_wmd.sh`, not a second implementation of the fix. The
launcher may present menu actions for apply, dry-run, verify, restore, support
bundle creation, and help, but behavior-changing work must delegate to the
canonical engine or existing tools.

`Install Fix.command` and `install.sh` are bootstrap entrypoints. They may clone
or update this repository and should open `Worms W.M.D Fix.command` for
interactive no-argument runs when that launcher is present. When command-line
flags are provided, `install.sh` must continue forwarding them to
`fix_worms_wmd.sh`.

The main installer runs the fix scripts in this logical order:

1. `scripts/01_build_agl_stub.sh` - build the AGL compatibility framework from
   `src/agl_stub.c`.
2. `scripts/02_replace_qt_frameworks.sh` - replace bundled Qt frameworks and
   plugins with Qt 5.15 assets.
3. `scripts/03_copy_dependencies.sh` - copy required dynamic libraries into the
   app bundle.
4. `scripts/04_fix_library_paths.sh` - rewrite install names to bundle-relative
   paths.
5. `scripts/06_fix_info_plist.sh` - update bundle metadata and display flags.
6. `scripts/07_fix_config_urls.sh` - upgrade known HTTP URLs and disable
   internal/staging URLs.
7. `scripts/05_verify_installation.sh` - verify framework, plugin, dependency,
   metadata, code-signing, quarantine, and config URL state.

Hard runtime verification runs before ad-hoc signing, and strict signature
verification remains inside the rollback boundary. Only afterward may the
installer clear quarantine, reset Qt window geometry, and commit.

Do not reorder these steps unless the verification contract is updated in the
same change.

## App Bundle Boundary

The fix may modify files inside the selected `Worms W.M.D.app` bundle and may
create user-owned backups, logs, cache files, and optional user LaunchAgents.
It must not modify system directories or require elevated privileges. Mutable
bundle directories, including `Contents/MacOS`, must resolve inside the selected
app rather than through a link to an external directory. Nested paths must not
contain control characters, unsupported entry types, escaping symlinks, or
hardlinked files that recursive signing could mutate outside the bundle.

The default app path is:

```bash
$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app
```

`GAME_APP` may point elsewhere. Always quote it because the bundle path contains
spaces. When `GAME_APP` is not set, user entrypoints enumerate common Steam
library, GOG, `/Applications`, `$HOME/Applications`, and `$HOME/Games`
app-bundle locations. Multiple installations require an explicit or interactive
selection and must not silently fall back to Steam.

## Backup And Restore Contract

Before destructive changes, the fix verifies a hidden staging backup, reserves
a final name with a hidden atomic lock, then publishes it under
`~/Documents/WormsWMD-Backup-*/`. Restore must cover:

- `Contents/Frameworks/`
- `Contents/PlugIns/`
- `Contents/MacOS/`, including the main executable and GOG Galaxy libraries
- `Contents/_CodeSignature/` when it existed before the fix
- `Contents/Info.plist` when backed up
- DataOSX config files when backed up
- CommonData config files when backed up
- `BACKUP_METADATA.tsv` with source-app and executable identity
- `BACKUP_MANIFEST.tsv` for checksum and size verification of new backups

When a game-bundle backup includes `BACKUP_MANIFEST.tsv`, restore and rollback
must verify it before copying files back and must verify the restored files
afterward. Backups without source metadata are legacy backups and may be
restored only with an explicit warning. A backup containing metadata that is
missing, malformed, duplicated, or not bound into its manifest is invalid, not
legacy.

Manifest verification must reject missing, changed, duplicate, unsupported,
control-character, and unrecorded non-directory entries. Version 2 records
symlink paths/targets; version 1 remains readable without symlink identity.

New automatic restores require a matching canonical app and storefront.
Metadata v2 requires a complete `MacOS` tree and staged replacement; v1 keeps
historical merge behavior. Legacy backups without source metadata require one
unambiguous installation. Failed verification is never reported as rollback.

Backup creation may repair the fixer's own stale AGL framework symlink layout
inside the backup copy before manifest validation. This self-heals repeated
installs from older fixer versions without mutating save data or trusting
symlinks that escape the backup root.

Save restore inspects one bounded copy, requires numeric Steam IDs, rejects
intermediate user links, and defaults inside canonical userdata. An external
`327030` target requires its exact canonical path plus `--yes`. Steam must be
stopped. Every root stages on its target filesystem; old trees remain until all
copies verify and roll back together. Expansion keeps the 8 GiB, half-free-space, and 512 MiB-reserve bounds.

## Qt Distribution Contract

The preferred Qt source is `dist/` plus its `.sha256`. Consumers inspect and use
one bounded owner-only copy. Profiles cap resources and reject unsafe archive
structure. Mutation requires Python 3.9+; diagnostics degrade without parsing.
Remote fallback must use a pinned commit for `dist/` contents. If a legacy
archive lacks `MANIFEST.txt`, the downloader generates and verifies a cache-local manifest.
Homebrew is a fallback, not the primary happy path.

When replacing the Qt archive:

- Update the matching checksum file.
- Validate the archive layout, package metadata, required frameworks/plugins,
  complete dependency closure, archive manifest when present, generated cache
  manifest, and readable x86_64 Mach-O slices.
- Resolve dependency source symlinks before applying provenance-prefix policy.
- Run the packaging or install verification relevant to the change.
- Update user docs if the version, source, or fallback behavior changes.

Installer and verifier success requires the runtime pieces the game needs to
launch: an AGL stub binary with an x86_64 slice, QtCore, QtGui, QtWidgets,
QtOpenGL, QtPrintSupport, QtDBus, QtSvg, `PlugIns/platforms/libqcocoa.dylib`,
`PlugIns/imageformats/libqsvg.dylib`, and the required bundled Qt dependency
dylibs. Missing required runtime inputs must fail before destructive replacement
where possible, and post-backup failures must trigger rollback.

Copied Qt framework binaries must be made owner-writable before
`install_name_tool` rewrites them. Package inputs may intentionally be
read-only, but the game-bundle copies are mutable installer working files.

`@rpath` is not an error by itself. Verification resolves run paths from the
loading binary and main executable, accepts targets only inside the selected
app bundle, and reports unresolved weak-load dependencies as optional warnings.
The weak-load policy applies consistently to `@rpath`, `@executable_path`, and
`@loader_path`. Unresolved strong dependencies and external absolute
dependencies remain errors. Direct token paths must remain inside `Contents`,
and relative dependency names are unportable errors. Intended
`install_name_tool` mutations must fail with their underlying error instead of
being silently ignored. Verification covers storefront dylibs in `MacOS`, every
framework/root dylib, and every installed plugin category.

When multiple local Qt packages are present, scripts should choose the highest
verified supported Qt 5.15.x version rather than the newest file by modification
time. The current `dist/` package is Qt 5.15.19 and must include a matching
checksum plus `SOURCE_PROVENANCE.tsv` lock before being documented as shipped.

Maintainer packages should be reproducible where possible: deterministic file
ordering, normalized timestamps from `SOURCE_DATE_EPOCH`, stable ownership in
the tar stream, `gzip -n`, and a generated `MANIFEST.txt`.

The reviewed bottle closure is `packaging/qt-homebrew-lock.tsv`; `dist/` keeps
generated evidence. Fetching bounds exact GHCR digest downloads, drops
cross-origin authorization, validates without `qmake`, and stages beside the
output. Replacement/cleanup requires its path-bound marker and explicit flag.

## Network Contract

Network access is limited to documented endpoints for repository downloads,
prebuilt Qt assets, update checks, preflight checks, and Apple-managed tool
installation prompts. Payloads that affect executable code must use HTTPS and
checksum verification. Bootstrap installers default to the latest stable
release tag; mainline bootstraps should also verify the exact release commit
when that commit is known. Mutable refs require explicit developer opt-in.
Preflight endpoint checks are diagnostic public page reachability probes for
Team17, Steam, and GOG; they must not be described as proof of multiplayer,
store authentication, or game-service health.

The project does not collect telemetry.

## Release Bundle Contract

`tools/build_release_bundle.sh` builds the player-facing release folder and zip
under `build/release/` by default. The bundle may include repository source,
scripts, tools, docs, the reviewed packaging lock, original assets, and verified `dist/` packages.
It must not include `.git`, local build output, downloaded sample projects,
game binaries, save files, support bundles, logs, secrets, or user data.

Release bundles must include `RELEASE_INFO.txt` and `RELEASE_MANIFEST.tsv`; a
zip requires a matching `.sha256`. Tagged GitHub releases also publish a
deterministic CycloneDX SBOM from the locked Qt provenance and attest the SBOM
against the release zip.

Visual assets bundled by this repository must be original or have a committed
redistribution license and attribution. Do not commit official Team17/Worms art
or third-party sample assets without documented permission.

## Logging And Diagnostics Contract

Fix logs are written under `~/Library/Logs/WormsWMD-Fix/` unless `LOG_FILE`
sets another regular `.log` path under `~/Library/Logs`. Debug tracing writes a
`.trace` file next to the selected log.

Launcher logs and crash reports are written under `~/Library/Logs/WormsWMD/`.
Diagnostics intended for bug reports should be collected with:

```bash
./tools/collect_diagnostics.sh
./tools/collect_diagnostics.sh --bundle
```

Diagnostics and reports must not expose secrets, private account data, or
unredacted sensitive config values. Diagnostics output should be sanitized by
default for issue reporting. Support bundles should sanitize the diagnostics
report, include macOS version, Rosetta package version when available, x86_64
execution status, sanitized installer history, runtime invariant status, Qt
package verification details, backup integrity status, and backup manifests
when available instead of copying full game or save contents. Support bundles
must not include raw `.log`, `.trace`, crash-log, save, game-binary, or private
config-file contents. Support-bundle archives should normalize tar owner/group
metadata so archive listings do not expose local account names.
The friendly launcher's support option should delegate to
`tools/collect_diagnostics.sh --bundle --bundle-output ~/Desktop` while
preserving the selected `GAME_APP`. Direct diagnostics with multiple detected
installations and no explicit target must report ambiguity instead of choosing
one. Support bundles should include sanitized run-path resolution, backup source
metadata, and one copy of byte-identical backup manifests.

## Validation Contract

For source-only changes, use the checks that match the blast radius:

```bash
./tools/validate_harness.sh
./tools/test_bootstrap_installer_safety.sh
./tools/test_dependency_parsing.sh
./tools/test_issue_10_regression.sh
./tools/test_issue_11_game_detection.sh
./tools/test_issue_12_agl_install_failure.sh
./tools/test_installer_rollback_regression.sh
./tools/test_mutation_safety.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_backup_saves_regression.sh
./tools/test_launcher_friction.sh
./tools/test_preflight_regression.sh
./tools/test_manifest_regression.sh
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

For runtime changes on a macOS machine with Worms W.M.D installed, also run the
relevant dry-run, verify, preflight, launcher, or diagnostics workflow.
