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
| Supply chain attacks | Pre-built packages require SHA256 verification |

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
| `/tmp/agl_stub_build/` | Temporary build directory | Automatic |

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
| Repository clone/update | `github.com` | HTTPS via git |
| Update check (optional) | `raw.githubusercontent.com` | HTTPS |
| Pre-flight network check (optional) | `ads.t17service.com`, `steamcommunity.com` | HTTPS |
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

The `check_updates.sh --download` option downloads a ZIP snapshot from GitHub without cryptographic signature verification. For maximum security, prefer `git pull` which uses SSH/HTTPS authentication.

## Download verification

Pre-built Qt framework packages undergo multiple verification steps:

1. **Source verification**: Downloaded only from the repository's `dist/` directory
2. **Checksum validation**: SHA256 hash must match the `.sha256` file
3. **Archive layout validation**: Only whitelisted paths are allowed:
   - `Frameworks/` and contents
   - `PlugIns/` and contents
   - `METADATA.txt`
4. **Path traversal protection**: Archives containing `../`, `/..`, or absolute paths are rejected
5. **Post-extraction verification**: Confirms expected directories exist

If any verification fails, the script falls back to Homebrew or exits with an error.

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
| `GAME_APP` | Must be a directory containing `Contents/MacOS/Worms W.M.D` |
| `INSTALL_DIR` | Checked for conflicts, backed up if exists |
| `LOG_FILE` | Created in user-writable location only |
| `QT_PREFIX` | Verified to contain expected Qt frameworks |

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
| Run `curl` (preflight) | Test network connectivity | None |

## Security audit checklist

Last audit: 2025-12-26

| Category | Status | Notes |
|----------|--------|-------|
| Command injection | Pass | No `eval` on user input, no unsafe shell expansion |
| Path traversal | Pass | Archive validation, no unvalidated path concatenation |
| Network security | Pass | HTTPS-only, TLS 1.2+, checksums required |
| Privilege escalation | Pass | No sudo/doas, no SUID, user-level only |
| Symlink attacks | Pass | `mktemp` for temp files, cleanup traps |
| Race conditions | Pass | Atomic operations where possible |
| Secret exposure | Pass | No credentials in fix code; game config secrets documented in report |
| Dependency security | Pass | Checksums for downloads, Homebrew fallback |
| Code signing | Pass | Ad-hoc signature applied, quarantine cleared |
| Input validation | Pass | Environment variables and user input validated |
| Game URL security | Pass | HTTP upgraded to HTTPS, staging URLs disabled |

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
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh
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
- Rosetta 2 installation (Apple Silicon)
- Game installation and fix status
- Runtime dependencies (FMOD, Steam API, libcurl)
- Network connectivity to Team17 services

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

**Restore command**:

```bash
./fix_worms_wmd.sh --restore
```

## Third-party components

| Component | Source | Verification |
|-----------|--------|--------------|
| Qt 5.15 | Pre-built in repo `dist/`, or Homebrew | SHA256 checksum |
| GLib, PCRE2, etc. | Bundled with Qt or from Homebrew | Transitive from Qt |

Pre-built Qt packages:
- Built from Homebrew Qt 5.15 on Intel macOS
- Packaged with `tools/package_qt_frameworks.sh`
- Stored in repo `dist/` with SHA256 checksums
- Architecture: x86_64 (runs under Rosetta 2 on Apple Silicon)

## Known limitations

1. **Pre-built packages are not signed**: The Qt framework tarball uses SHA256 checksums but not cryptographic signatures. The checksum file is in the same repository.

2. **Update downloads lack signatures**: `check_updates.sh --download` retrieves code without signature verification. Use `git pull` for authenticated updates.

3. **Ad-hoc code signature**: The app is signed with an ad-hoc signature, not a Developer ID. This may trigger Gatekeeper warnings on some systems.

4. **Backup restore is not validated**: `backup_saves.sh` does not validate tar archive contents before extraction. Only restore backups you created yourself.

5. **Game config secrets**: The original game ships with API credentials in config files. These are documented in TEAM17_DEVELOPER_REPORT.md (redacted) for Team17's awareness. The fix does not modify these credentials.

## Reporting security issues

**Do not open a public issue for security vulnerabilities.**

Instead, email the maintainer directly with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You will receive a response within 48 hours acknowledging the report.
