# Security

This document describes the security model, threat mitigations, and audit status for the Worms W.M.D macOS fix.

## Security overview

The fix is designed to be:

- **Transparent**: Open source and fully auditable
- **Minimal**: Only modifies files within the game bundle
- **Reversible**: Creates backups before any changes
- **Unprivileged**: Never requires `sudo` or elevated permissions
- **Verified**: Downloads require cryptographic checksum validation

## Threat model

This fix is designed to be safe against:

| Threat | Mitigation |
|--------|------------|
| Malicious code injection | All scripts use `set -euo pipefail`, no `eval` on user input |
| Path traversal attacks | Archive validation rejects `../` and absolute paths |
| Man-in-the-middle attacks | HTTPS with TLS 1.2+ required, checksums verified |
| Insecure game URLs | HTTP URLs upgraded to HTTPS, staging URLs disabled |
| Privilege escalation | No `sudo`, no SUID, runs entirely as current user |
| Symlink attacks | Temp files use `mktemp`, cleanup traps prevent dangling files |
| Supply chain attacks | Pre-built packages require SHA256, metadata, manifest, and architecture verification |

## What the fix modifies

### Files modified inside the game bundle

| Location | Action | Purpose |
|----------|--------|---------|
| `Contents/Frameworks/` | Replace Qt frameworks | Upgrade Qt 5.3.2 to 5.15.x |
| `Contents/Frameworks/AGL.framework/` | Add stub library | Satisfy removed AGL dependency |
| `Contents/Frameworks/*.dylib` | Add dependency libraries | Bundle required runtime libraries |
| `Contents/PlugIns/` | Replace Qt plugins | Update platform and image plugins |
| `Contents/Info.plist` | Update metadata | Add bundle ID, HiDPI flags, min version |
| `Contents/Resources/DataOSX/*.txt` | Update URLs | Use HTTPS, disable internal staging URLs |
| `Contents/Resources/CommonData/*.txt` | Update URLs | Use HTTPS for analytics/HTTP config |

### Files created outside the game bundle

| Location | Purpose | Cleanup |
|----------|---------|---------|
| `~/Documents/WormsWMD-Backup-*/` | Backups of original files | Manual |
| `~/Documents/WormsWMD-SaveBackups/` | Save game backups (optional tool) | Manual |
| `~/Library/Logs/WormsWMD-Fix/` | Fix operation logs | Manual |
| `~/Library/Logs/WormsWMD/` | Launcher logs and crash reports | Manual |
| `~/.cache/wormswmd-fix/` | Cached Qt frameworks | Manual or `--force` |
| `~/Library/LaunchAgents/com.wormswmd.fix.watcher.plist` | Optional update watcher | `--uninstall` |
| `${TMPDIR:-/tmp}/agl_stub_build.*/` | Main installer AGL build directory | Automatic |

## What the fix does NOT do

- Modify any system files or directories
- Require or use `sudo`, `doas`, or any privilege escalation
- Collect, transmit, or store any personal data
- Access any network services except those listed below
- Install persistent background services (unless you opt in)
- Modify `PATH`, `DYLD_LIBRARY_PATH`, or other environment variables

## Network security

### Connections made

| Purpose | Destination | Security |
|---------|-------------|----------|
| Qt framework download | `github.com` (repo dist/) | HTTPS + SHA256 checksum |
| Release bundle download | `github.com` releases | HTTPS + SHA256 checksum + artifact attestation |
| Repository clone/update | `github.com` | HTTPS via git |
| Terminal bootstrap script (optional) | `raw.githubusercontent.com` pinned release tag | HTTPS |
| Update check (optional) | `api.github.com`, `github.com` release assets | HTTPS + SHA256 checksum for downloads |
| Pre-flight public endpoint check (optional) | `www.team17.com/games/worms-w-m-d`, `store.steampowered.com/app/327030/Worms_WMD/`, `www.gog.com/en/game/worms_wmd` | HTTPS |
| Maintainer Qt provenance rebuild | `formulae.brew.sh`, `ghcr.io` Homebrew bottle blobs | HTTPS + pinned bottle SHA256 |
| Rosetta 2 install | Apple servers | System-managed |
| Xcode CLT install | Apple servers | System-managed |

### Network security measures

All network operations use:

- **HTTPS only**: `--proto '=https'` enforced on curl
- **TLS 1.2 minimum**: `--tlsv1.2` enforced on curl
- **Retry with backoff**: `--retry 3 --retry-delay 1 --retry-connrefused`
- **Timeouts**: All requests have `--max-time` limits (10-300 seconds)
- **Checksum verification**: SHA256 required for pre-built packages

No analytics or telemetry are used, and network access is limited to the endpoints listed above.

### Security note on updates

The `check_updates.sh --download` option downloads the latest release zip and
matching `.sha256` file, then verifies the checksum before leaving the zip in
`~/Downloads`. GitHub release attestations can be verified separately with
`gh attestation verify`.

## Download verification

Release bundles publish both a zip and a matching SHA-256 checksum file. For
the `v1.7.2` release:

```bash
cd ~/Downloads
shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.2.zip.sha256
```

Expected output:

```text
WormsWMD-macOS-Fix-v1.7.2.zip: OK
```

Release bundles also receive GitHub artifact attestations from the release
workflow:

```bash
gh attestation verify WormsWMD-macOS-Fix-v1.7.2.zip --repo cboyd0319/WormsWMD-macOS-Fix
```

The checksum verifies the file content. The attestation verifies that GitHub
Actions built the asset from this repository.

Pre-built Qt framework packages undergo multiple verification steps:

1. **Source verification**: Downloaded only from local `dist/` or the pinned
   release commit's `dist/` directory
2. **Checksum validation**: SHA256 hash must match the `.sha256` file
3. **Version and metadata validation**: Package names and `METADATA.txt` must
   agree on a numeric Qt 5.15.x version and x86_64 architecture
4. **Archive layout validation**: Only whitelisted paths are allowed:
   - `Frameworks/` and contents
   - `PlugIns/` and contents
   - `METADATA.txt`
   - `MANIFEST.txt`
   - `SOURCE_PROVENANCE.tsv`
5. **Path traversal and link protection**: Archives containing `../`, `/..`,
   absolute paths, unsafe symlink targets, hardlinks, or special files are
   rejected
6. **Required content validation**: Required Qt frameworks, the Cocoa platform
   plugin, metadata, and plugin directories must be present after extraction
7. **Architecture validation**: Framework and plugin binaries must contain an
   `x86_64` Mach-O slice
8. **Package manifest validation**: `MANIFEST.txt` is verified when present in
   the archive; extracted cache directories get a generated manifest when the
   legacy archive does not include one
9. **Post-extraction verification**: Confirms expected directories and the
   extracted cache manifest exist before use

If any verification fails, the script falls back to Homebrew only when a valid Intel Homebrew Qt install is present; otherwise it exits before replacing game frameworks.

## Code signing

The fix applies an ad-hoc code signature to the modified game bundle:

```bash
codesign --force --deep --sign - "$GAME_APP"
```

This signature:
- Allows the app to run without Gatekeeper warnings
- Does not require an Apple Developer account
- Is not notarized (Apple notarization would require the original developer)

The signature can be verified with:

```bash
codesign -dv --verbose=4 "path/to/Worms W.M.D.app"
```

## Optional background process

The update watcher (`tools/watch_for_updates.sh --install`) installs a LaunchAgent that:

- Monitors for Steam updates that overwrite the fix
- Runs locally with no network access
- Uses `launchctl bootstrap gui/$UID` (user-level, not system-level)
- Can be completely removed with `--uninstall`

The LaunchAgent plist is created at:
```
~/Library/LaunchAgents/com.wormswmd.fix.watcher.plist
```

## Input validation

### Environment variables

User-controllable environment variables are validated:

| Variable | Validation |
|----------|------------|
| `GAME_APP` | Must be a directory containing `Contents/MacOS/Worms W.M.D`; writable bundle subpaths must not be symlinks or resolve outside `Contents` |
| `INSTALL_DIR` | Refuses system paths, home directory, non-empty non-repo directories, and Git repositories with a different remote |
| `INSTALL_REF` | Defaults to pinned release `v1.7.2`; mainline maintenance bootstraps also verify the exact release commit when known; non-default refs require `WORMSWMD_ALLOW_UNPINNED_REF=1` |
| `LOG_FILE` | Must be a regular `.log` path under `~/Library/Logs` |
| `QT_PREFIX` | Verified to contain expected Qt frameworks; direct custom Homebrew prefixes require explicit opt-in |

### User input

All interactive prompts:
- Use `read ... < /dev/tty` for reliable input even when piped
- Validate input before use (e.g., numeric range checks)
- Default to safe options (e.g., "no" for destructive operations)

## Permissions required

| Permission | Why needed | Files affected |
|------------|------------|----------------|
| Read game directory | Back up and verify | Game bundle |
| Write game directory | Apply the fix | Game bundle |
| Read `/usr/local/` | Copy Qt libraries (Homebrew fallback) | Homebrew cellar |
| Write `~/Documents/` | Create backups | Backup directories |
| Write `~/Library/Logs/` | Write logs | Log files |
| Write `~/.cache/` | Cache Qt frameworks | Cache directory |
| Run `clang` | Compile AGL stub | Temp build files |
| Run `launchctl` | Install/remove update watcher | LaunchAgents |
| Run `osascript` | Notifications (optional tools) | None |
| Run `pbcopy` | Copy diagnostics (optional) | Clipboard |
| Run `curl` (preflight) | Test optional public Team17, Steam, and GOG page reachability | None |

## Security audit checklist

Last audit: 2026-06-22

| Category | Status | Notes |
|----------|--------|-------|
| Command injection | Pass | No `eval` on user input, no unsafe shell expansion |
| Path traversal | Pass | Qt and save-backup archive validation, link rejection, no unvalidated path concatenation |
| Network security | Pass | HTTPS-only, TLS 1.2+, checksums required |
| Privilege escalation | Pass | No sudo/doas, no SUID, user-level only |
| Symlink attacks | Pass | Main installer uses a per-run `mktemp` build directory, cleanup traps, bundle containment checks, and archive link rejection |
| Race conditions | Pass | Atomic operations where possible |
| Secret exposure | Pass | No credentials in fix code; game config secrets documented in report |
| Support bundle privacy | Pass | Sanitized bundles include OS, Rosetta, installer-history, runtime-invariant, Qt-package, and backup-integrity context without raw logs, saves, game binaries, or private config contents |
| Dependency security | Pass | Checksums, metadata, manifests, and x86_64 slice checks for pre-built Qt |
| Code signing | Pass | Ad-hoc signature applied, quarantine cleared |
| Input validation | Pass | Environment variables and user input validated |
| Game URL security | Pass | HTTP upgraded to HTTPS, staging URLs disabled |
| Backup restore | Pass | Game backups validate manifests and safe symlinks; save archives reject links and special files before restore; legacy backups are flagged |
| Release provenance | Pass | Release assets have SHA-256 checksums and GitHub artifact attestations |

## Verifying the fix

### Review the code

```bash
# Main fix script
less fix_worms_wmd.sh

# Individual steps
ls -la scripts/
less scripts/01_build_agl_stub.sh

# Tools
ls -la tools/
less tools/check_updates.sh

# AGL stub source
less src/agl_stub.c
```

### Run ShellCheck

```bash
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
```

### Preview changes (dry run)

```bash
./fix_worms_wmd.sh --dry-run
```

### Verify after applying

```bash
./fix_worms_wmd.sh --verify
```

### Run pre-flight check

```bash
./tools/preflight_check.sh
```

This verifies:
- macOS version and architecture
- Rosetta 2 installation and package version when available (Apple Silicon)
- Game installation and fix status
- Runtime dependencies (FMOD, Steam API, libcurl)
- Optional public Team17, Steam, and GOG page reachability

### Inspect the AGL stub

```bash
# View source
cat src/agl_stub.c

# Check compiled binary
file "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/AGL.framework/Versions/A/AGL"

# Verify architecture
lipo -archs "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/AGL.framework/Versions/A/AGL"
```

## Backups and recovery

The fix automatically creates a backup before making changes:

**Backup location**: `~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS/`

**Backup contents**:
- `Frameworks/` - Original Qt frameworks and libraries
- `PlugIns/` - Original Qt plugins
- `Info.plist` - Original app metadata
- `DataOSX/` - Original configuration files
- `BACKUP_MANIFEST.tsv` - SHA256 and size manifest for backup verification

**Restore command**:

```bash
./fix_worms_wmd.sh --restore
```

## Third-party components

| Component | Source | Verification |
|-----------|--------|--------------|
| Qt 5.15.x | Pre-built in repo `dist/`, or Intel Homebrew/custom prefix fallback | SHA256 checksum, metadata, archive/generated manifest, x86_64 slices, supported-series check |
| GLib, PCRE2, etc. | Bundled with Qt or from Homebrew | Transitive from Qt |

Pre-built Qt packages:
- Built from a checksum-locked Homebrew Qt 5.15.19 x86_64 bottle closure
- Packaged with `tools/package_qt_frameworks.sh`
- Stored in repo `dist/` with SHA256 checksums and source provenance
- Architecture: x86_64 (runs under Rosetta 2 on Apple Silicon)

As of 2026-06-18, the current Homebrew `qt@5` stable formula is Qt 5.15.19.
This repository ships `dist/qt-frameworks-x86_64-5.15.19.tar.gz` with
`dist/qt-frameworks-x86_64-5.15.19.tar.gz.sha256` and
`dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv`.

Qt package supply-chain process:

1. `dist/qt-frameworks-x86_64-5.15.19.source-provenance.tsv` locks every
   Homebrew bottle in the Qt runtime closure by formula name, version, bottle
   tag, GHCR blob URL, bottle SHA256, upstream source SHA256, Homebrew formula
   SHA256, and Homebrew tap commit.
2. `tools/fetch_qt_homebrew_bottles.rb --lock ... --output ...` fetches those
   exact blobs, verifies every bottle SHA256 before extraction, builds an
   isolated Homebrew-like prefix, rewrites Homebrew bottle placeholders to that
   prefix, verifies no placeholders remain, and confirms QtCore has an x86_64
   Mach-O slice.
3. `tools/package_qt_frameworks.sh` packages only Qt 5.15.x inputs, copies the
   runtime frameworks, plugins, and dylib closure, prunes non-runtime framework
   headers, embeds `SOURCE_PROVENANCE.tsv`, writes `MANIFEST.txt`, and creates
   the archive plus checksum.
4. `scripts/download_qt_frameworks.sh --check` validates the committed archive
   checksum, metadata, whitelisted layout, tar metadata, manifest, required
   runtime files, and x86_64 Mach-O slices before installer use.

## Known limitations

1. **Pre-built packages are not signed**: The pre-built Qt path uses SHA256 checksums, metadata, archive or generated cache manifests, and binary-slice checks, but not cryptographic package signatures. The checksum file is in the same repository.

2. **Update downloads are checksum-verified but not independently signed**: `check_updates.sh --download` verifies the release zip checksum. Use `gh attestation verify` for release provenance.

3. **Ad-hoc code signature**: The app is signed with an ad-hoc signature, not a Developer ID. This may trigger Gatekeeper warnings on some systems.

4. **Legacy backups cannot be fully verified**: Backups created before manifest support can still be restored, but the scripts warn that they lack checksum manifests.

5. **Game config secrets**: The original game ships with confirmed API credentials in config files. These are documented in TEAM17_DEVELOPER_REPORT.md (redacted) for Team17's awareness. The fix does not modify these credentials.

## Reporting security issues

**Do not open a public issue for security vulnerabilities.**

Instead, email the maintainer directly with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You will receive a response within 48 hours acknowledging the report.
