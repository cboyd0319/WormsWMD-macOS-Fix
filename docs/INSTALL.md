# Install

This guide covers the friendly release path, manual installation steps, and
restore options.

## For most players

Use the release bundle:

1. Download the latest release zip from:
   https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest
2. Optionally download the matching `.zip.sha256` file and verify it:
   `shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.5.zip.sha256`
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
curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.7.5/install.sh | bash
```

With no command-line flags and an interactive Terminal, `install.sh` opens the
same friendly launcher menu. When flags are provided, it forwards them directly
to `fix_worms_wmd.sh`. By default, the bootstrap pins the cloned repository to
release `v1.7.5`. The release-tag bootstrap pins the tag and the mainline
maintenance bootstrap verifies the exact release commit. Non-default refs
require `WORMSWMD_ALLOW_UNPINNED_REF=1`.

## Preview changes

To see what the fix does without applying it, run:

```bash
./fix_worms_wmd.sh --dry-run
```

## Install manually

Use the canonical fixer even when installing manually. It creates a backup,
verifies the runtime, and rolls back automatically if a mutating step fails.
The helper scripts under `scripts/` are internal building blocks and do not
provide the same recovery path when run one by one.

```bash
git clone --branch v1.7.5 --depth 1 https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix

# Optional: set this only when the game is outside the usual Steam/GOG paths.
export GAME_APP="/path/to/Worms W.M.D.app"

./fix_worms_wmd.sh --dry-run
./fix_worms_wmd.sh
```

If the pre-built Qt package is unavailable, install Intel Homebrew Qt and let
the fixer detect it:

```bash
arch -x86_64 /usr/local/bin/brew install qt@5
./fix_worms_wmd.sh
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
present and cancels instead of restoring from a mismatched backup. New backups
are published only after verification and record their source app/storefront in
`BACKUP_METADATA.tsv`, so a Steam backup cannot be applied to GOG or vice versa.
Metadata that is missing from its manifest or malformed is rejected. Older
backups without source metadata are restored with a warning only when the
selected installation is unambiguous.

### Restore manually

Prefer automatic restore when possible because it performs manifest validation.
Manual restore is useful for inspection or recovery, but it bypasses the
automated file-integrity checks. The example below reproduces the path and
storefront identity checks, but you must inspect the manifest before copying.

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

# New backups must match the selected app.
if [[ -f "$BACKUP_DIR/BACKUP_METADATA.tsv" ]]; then
  BACKUP_GAME_APP=$(awk -F '\t' '$1 == "game_app_path" {sub(/^[^\t]*\t/, ""); print; exit}' "$BACKUP_DIR/BACKUP_METADATA.tsv")
  BACKUP_GAME_SOURCE=$(awk -F '\t' '$1 == "game_source" {print $2; exit}' "$BACKUP_DIR/BACKUP_METADATA.tsv")
  SELECTED_GAME_APP=$(cd "$GAME_APP" && pwd -P)
  [[ "$BACKUP_GAME_APP" == "$SELECTED_GAME_APP" ]] || {
    echo "Backup belongs to a different game installation." >&2
    exit 1
  }

  GAME_EXEC="$GAME_APP/Contents/MacOS/Worms W.M.D"
  GAME_DEPENDENCIES=$(otool -arch x86_64 -L "$GAME_EXEC" 2>/dev/null || true)
  if grep -Fqi 'libGalaxy.dylib' <<< "$GAME_DEPENDENCIES"; then
    SELECTED_GAME_SOURCE=gog
  elif grep -Fqi 'libsteam_api.dylib' <<< "$GAME_DEPENDENCIES"; then
    SELECTED_GAME_SOURCE=steam
  else
    echo "Could not identify the selected Steam or GOG installation." >&2
    exit 1
  fi
  [[ "$BACKUP_GAME_SOURCE" == "$SELECTED_GAME_SOURCE" ]] || {
    echo "Backup belongs to a different storefront." >&2
    exit 1
  }
fi

rm -rf "$GAME_APP/Contents/Frameworks"
rm -rf "$GAME_APP/Contents/PlugIns"
cp -R "$BACKUP_DIR/Frameworks" "$GAME_APP/Contents/"
cp -R "$BACKUP_DIR/PlugIns" "$GAME_APP/Contents/"

# Restore original launch files, executable, and storefront libraries.
if [[ -d "$BACKUP_DIR/MacOS" ]]; then
  cp -R "$BACKUP_DIR/MacOS/." "$GAME_APP/Contents/MacOS/"
fi

# Restore or remove fixer-created signature resources according to metadata.
if [[ -f "$BACKUP_DIR/BACKUP_METADATA.tsv" ]]; then
  SIGNATURE_PRESENT=$(awk -F '\t' '$1 == "code_signature_present" {print $2; exit}' "$BACKUP_DIR/BACKUP_METADATA.tsv")
  rm -rf "$GAME_APP/Contents/_CodeSignature"
  if [[ "$SIGNATURE_PRESENT" == "true" && -d "$BACKUP_DIR/_CodeSignature" ]]; then
    cp -R "$BACKUP_DIR/_CodeSignature" "$GAME_APP/Contents/"
  fi
fi

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
