# Install

This guide covers the friendly release path, manual installation steps, and
restore options.

## For most players

Use the release bundle:

1. Download the latest release zip from:
   https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest
2. Optionally download the matching `.zip.sha256` file and verify it:
   `shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.2.zip.sha256`
3. Unzip it.
4. Open `README_FIRST.txt`.
5. Double-click `Worms W.M.D Fix.command`.
6. Choose option 1.
7. Launch when prompted, or choose option 7 later.

On macOS 27 Golden Gate, Rosetta may need to be installed again after an
upgrade. Worms needs Rosetta because it is an older Intel Mac game. If launch
readiness reports that Rosetta is unavailable, run:

```bash
softwareupdate --install-rosetta --agree-to-license
```

The launcher also includes:

- option 2 to preview changes
- option 3 to check whether the game is ready to launch
- option 4 to restore from backup
- option 5 to create a support bundle on the Desktop
- option 6 to open the simple help file
- option 7 to launch Worms W.M.D

If macOS blocks the launcher, right-click `Worms W.M.D Fix.command`, choose
**Open**, then choose **Open** again.

## Bootstrap installer

If you only downloaded `Install Fix.command`, double-click it. It clones or
updates this repository under `~/.wormswmd-fix` and opens the friendly launcher
when it is available.

The bootstrap installers only update an existing checkout of this repository.
They refuse to move or overwrite non-empty directories that are not this fix,
and they refuse Git repositories with a different remote.

Terminal users can use:

```bash
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.7.2/install.sh | bash
```

With no command-line flags and an interactive Terminal, `install.sh` opens the
same friendly launcher menu. When flags are provided, it forwards them directly
to `fix_worms_wmd.sh`. By default, the bootstrap pins the cloned repository to
release `v1.7.2`. The release-tag bootstrap pins the tag and the next mainline
maintenance commit pins the exact release commit after the tag exists.
Non-default refs require `WORMSWMD_ALLOW_UNPINNED_REF=1`.

## Preview changes

To see what the fix does without applying it, run:

```bash
./fix_worms_wmd.sh --dry-run
```

## Install manually

Run these scripts in order:

```bash
git clone --branch v1.7.2 --depth 1 https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix

# Use an isolated build directory for the AGL stub.
export BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agl_stub_build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Step 1: Build the AGL stub library
./scripts/01_build_agl_stub.sh

# Prepare the pre-built Qt framework package.
QT_OUTPUT="$(./scripts/download_qt_frameworks.sh)"
QT_EXTRACT_DIR="$(printf '%s\n' "$QT_OUTPUT" | tail -1)"
if [[ ! -d "$QT_EXTRACT_DIR/Frameworks" ]]; then
  echo "Pre-built Qt package is unavailable. Use the Homebrew fallback below."
  exit 1
fi
export QT_SOURCE=prebuild
export QT_PREFIX="$QT_EXTRACT_DIR"

# Step 2: Replace Qt frameworks
./scripts/02_replace_qt_frameworks.sh

# Step 3: Copy required dependencies
./scripts/03_copy_dependencies.sh

# Step 4: Fix all library path references
./scripts/04_fix_library_paths.sh

# Step 5: Fix Info.plist metadata
./scripts/06_fix_info_plist.sh

# Step 6: Secure config URLs
./scripts/07_fix_config_urls.sh

# Step 7: Verify the installation
./scripts/05_verify_installation.sh
```

If the pre-built Qt package is unavailable, install Intel Homebrew Qt and set:

```bash
export QT_SOURCE=homebrew
export QT_PREFIX=/usr/local/opt/qt@5
```

## Set a custom game location

The installer auto-detects common Steam, GOG, Applications, and Games-folder
locations. If your game is still in a non-standard location, set the `GAME_APP`
variable:

```bash
GAME_APP="/path/to/Worms W.M.D.app" ./fix_worms_wmd.sh
```

Common GOG locations include:

```bash
GAME_APP="$HOME/GOG Games/Worms W.M.D/Worms W.M.D.app" ./fix_worms_wmd.sh
GAME_APP="$HOME/GOG Games/Worms WMD/Worms W.M.D.app" ./fix_worms_wmd.sh
```

## Verify only

To check whether the fix is applied without making changes:

```bash
./fix_worms_wmd.sh --verify
```

## Restore original files

The fix creates a timestamped backup before making changes.

### Restore automatically

```bash
./fix_worms_wmd.sh --restore
```

Automatic restore verifies the backup manifest when `BACKUP_MANIFEST.tsv` is
present and cancels instead of restoring from a mismatched backup. Older backups
without a manifest are treated as legacy backups and restored with a warning.

### Restore manually

Prefer automatic restore when possible because it performs manifest validation.
Manual restore is useful for inspection or recovery, but it bypasses the
automated manifest checks.

```bash
# Find your backup
ls ~/Documents/WormsWMD-Backup-*

# Restore (replace YYYYMMDD-HHMMSS with your backup timestamp)
BACKUP_DIR=~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS
GAME_APP="$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"

# Inspect the manifest if one exists.
if [[ -f "$BACKUP_DIR/BACKUP_MANIFEST.tsv" ]]; then
  sed -n '1,20p' "$BACKUP_DIR/BACKUP_MANIFEST.tsv"
fi

rm -rf "$GAME_APP/Contents/Frameworks"
rm -rf "$GAME_APP/Contents/PlugIns"
cp -R "$BACKUP_DIR/Frameworks" "$GAME_APP/Contents/"
cp -R "$BACKUP_DIR/PlugIns" "$GAME_APP/Contents/"

# Restore Info.plist (if backed up)
if [[ -f "$BACKUP_DIR/Info.plist" ]]; then
  cp "$BACKUP_DIR/Info.plist" "$GAME_APP/Contents/Info.plist"
fi

# Restore config files (if backed up)
if [[ -d "$BACKUP_DIR/DataOSX" ]]; then
  mkdir -p "$GAME_APP/Contents/Resources/DataOSX"
  cp -R "$BACKUP_DIR/DataOSX/." "$GAME_APP/Contents/Resources/DataOSX/"
fi
if [[ -d "$BACKUP_DIR/CommonData" ]]; then
  mkdir -p "$GAME_APP/Contents/Resources/CommonData"
  cp -R "$BACKUP_DIR/CommonData/." "$GAME_APP/Contents/Resources/CommonData/"
fi
```
