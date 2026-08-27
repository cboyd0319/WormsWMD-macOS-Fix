# Tools

The `tools/` directory includes helper utilities for backups, diagnostics,
launch options, packaging, update checks, and harness validation.

## Pre-flight check

Verify your system is ready before launching the game:

```bash
./tools/preflight_check.sh
./tools/preflight_check.sh --verbose
./tools/preflight_check.sh --quick
```

This checks:
- macOS version and architecture
- Rosetta 2 status and package version when available (Apple Silicon)
- Game installation and fix status
- Runtime dependencies (FMOD, Steam API, libcurl)
- Optional public reachability to Team17, Steam, and GOG Worms W.M.D pages
  (skip with `--quick`)

Note: Public endpoint checks require `curl`. Use `--quick` to skip them.

## Save game backup

Back up and restore your save games, settings, and replays:

```bash
./tools/backup_saves.sh
./tools/backup_saves.sh --list
./tools/backup_saves.sh --location
./tools/backup_saves.sh --restore
./tools/backup_saves.sh --restore ~/Documents/WormsWMD-SaveBackups/saves-20251225-120000.tar.gz
```

New save backups include a `MANIFEST.tsv` file. Restore rejects exact/canonical
duplicate members, control-character paths, links, and special entries before
use; it verifies the manifest, stages each save tree, replaces the backed-up
roots, and checks that stale files did not survive. Older legacy backups that
predate manifests restore with an explicit warning.

## Steam update watcher

Steam's **Verify integrity of game files** overwrites the fix. Use the watcher to detect when this happens:

```bash
./tools/watch_for_updates.sh --check
./tools/watch_for_updates.sh --daemon &
./tools/watch_for_updates.sh --install
./tools/watch_for_updates.sh --uninstall
```

The watcher uses the same common game discovery as the installer when
`GAME_APP` is not set, so it can check common Steam, GOG, Applications, and
Games-folder installs. When installed as a LaunchAgent, it persists the selected
`GAME_APP` so automatic reapply targets the same bundle.

## Steam launch options integration

Use the enhanced launcher with Steam for crash reporting:

1. Right-click **Worms W.M.D** in Steam → **Properties**
2. In **Launch Options**, enter:
   ```
   "/path/to/WormsWMD-macOS-Fix/tools/launch_worms.sh" --steam %command%
   ```

## Update checker

Check for new versions of the fix:

```bash
./tools/check_updates.sh
./tools/check_updates.sh --quiet
./tools/check_updates.sh --download
```

`--download` retrieves the latest release zip and its matching `.sha256` file,
then verifies the checksum before leaving the zip in `~/Downloads`.

## Controller helper

Diagnose controller connectivity and get configuration tips:

```bash
./tools/controller_helper.sh
./tools/controller_helper.sh --info
./tools/controller_helper.sh --test
```

## Diagnostics collector

Gather system information for bug reports:

```bash
./tools/collect_diagnostics.sh
./tools/collect_diagnostics.sh --output ~/Desktop/worms-diagnostics.txt
./tools/collect_diagnostics.sh --copy
./tools/collect_diagnostics.sh --full --output ~/Desktop/worms-full-diagnostics.txt
./tools/collect_diagnostics.sh --bundle
./tools/collect_diagnostics.sh --bundle --bundle-output ~/Desktop
```

Diagnostics output and support bundles are sanitized for issue reporting. The
collector redacts home-account paths, external volume paths, temporary paths,
email addresses, and common secret-like key/value strings. Support bundles
contain diagnostics, macOS version, Rosetta package version when available,
x86_64 execution status, sanitized installer history, runtime invariant status,
pre-built Qt package verification details, backup integrity status, and
deduplicated backup manifests. They also report the selected installation,
Mach-O run paths, resolved or optional executable dependencies, and backup
storefront metadata. They do not include raw logs, crash logs, save files, game
binaries, or private config file contents. The support-bundle
archive also normalizes tar owner and group metadata so it does not expose the
local macOS account name. Terminal escape sequences and other C0/DEL controls
are removed from support text while TSV tabs remain intact.

If more than one installation is detected, direct diagnostics require
`GAME_APP`. The friendly launcher prompts once and preserves that selection for
apply, verify, support, and launch actions.

## Enhanced launcher

Launch the game with extra logging and debug options:

```bash
./tools/launch_worms.sh --log
./tools/launch_worms.sh --check-fix --log
./tools/launch_worms.sh --safe-mode --log
./tools/launch_worms.sh --log --log-file ~/Library/Logs/WormsWMD/worms-launch.log
./tools/launch_worms.sh --qt-debug --opengl-debug --log --verbose
./tools/launch_worms.sh --no-crash-report
```

Log files must be regular `.log` files under `~/Library/Logs/`. Crash reports
are saved to `~/Library/Logs/WormsWMD/crashes/`. When `GAME_APP` is not set,
the launcher auto-detects common Steam, GOG, Applications, and Games-folder
installs before launching.

## Maintainer utilities

Validate the repository documentation harness after Markdown, agent instruction,
or docs-topology changes:

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
./tools/test_qt_version_pinning.sh
```

Check or refresh the pre-built Qt package used by the installer:

```bash
./scripts/download_qt_frameworks.sh --check
./scripts/download_qt_frameworks.sh --force
```

`scripts/download_qt_frameworks.sh --check` validates local package checksums,
metadata, required files, safe tar layout, archive manifests when present, and
x86_64 binary slices before reporting the pre-built Qt package as available.
Before installer use, extracted cache directories have a verified manifest;
legacy archives get one generated after extraction. Remote fallback checks the
pinned release commit for `dist/` contents.

`tools/package_qt_frameworks.sh` accepts either Intel Homebrew `qt@5` or an
explicit Qt prefix. It writes deterministic gzip archives using
`SOURCE_DATE_EPOCH`, emits `METADATA.txt` and `MANIFEST.txt`, prunes framework
headers from the runtime package, and is intended for maintainers replacing the
distribution archive in `dist/`. The packager and installer fallback reject Qt
versions outside the supported 5.15.x series. `QT_DEP_PREFIX` may be set when
packaging from an isolated Homebrew-like prefix whose transitive dylib
dependencies are outside `QT_PREFIX`. `QT_SOURCE_PROVENANCE_FILE` embeds the
Homebrew bottle lock as `SOURCE_PROVENANCE.tsv` in the archive.

Rebuild the committed Qt 5.15.19 runtime package from the pinned Homebrew
bottle lock:

```bash
./tools/fetch_qt_homebrew_bottles.rb \
  --lock dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv \
  --output /tmp/wormswmd-qt51519-prefix

SOURCE_DATE_EPOCH=1781740800 \
QT_PREFIX=/tmp/wormswmd-qt51519-prefix/opt/qt@5 \
QT_DEP_PREFIX=/tmp/wormswmd-qt51519-prefix \
QT_PACKAGE_VERSION=5.15.19 \
QT_SOURCE_PROVENANCE_FILE=dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv \
./tools/package_qt_frameworks.sh --output dist --version 5.15.19

(cd dist && shasum -a 256 -c qt-frameworks-x86_64-5.15.19.tar.gz.sha256)
./scripts/download_qt_frameworks.sh --check
```

To intentionally refresh the bottle lock for a newer Qt 5.15.x artifact, write
a new lock from current Homebrew metadata with an explicit `--version`, inspect
the diff, then rebuild:

```bash
./tools/fetch_qt_homebrew_bottles.rb \
  --formula qt@5 \
  --version 5.15.19 \
  --tag sonoma \
  --output /tmp/wormswmd-qt51519-prefix \
  --write-lock dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv
```

Build the player-facing release folder and zip:

```bash
./tools/build_release_bundle.sh --version local-smoke --skip-zip
./tools/build_release_bundle.sh --version local-smoke
```

The release builder copies the friendly launcher, bootstrap installers, docs,
assets, source, tools, scripts, and `dist/` package into
`build/release/WormsWMD-macOS-Fix-VERSION/`. It writes `RELEASE_INFO.txt`,
`RELEASE_MANIFEST.tsv`, an optional zip, and a `.sha256` file for the zip.
