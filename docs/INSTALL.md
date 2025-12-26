# Install

This guide covers manual installation steps and restore options.

## Preview changes

To see what the fix does without applying it, run:

```bash
./fix_worms_wmd.sh --dry-run
```

## Install manually

Run these scripts in order:

```bash
cd WormsWMD-macOS-Fix

# Step 1: Build the AGL stub library
./scripts/01_build_agl_stub.sh

# Step 2: Replace Qt frameworks
./scripts/02_replace_qt_frameworks.sh

# Step 3: Copy required dependencies
./scripts/03_copy_dependencies.sh

# Step 4: Fix all library path references
./scripts/04_fix_library_paths.sh

# Step 5: Verify the installation
./scripts/05_verify_installation.sh

# Step 6 (optional): Fix Info.plist metadata
./scripts/06_fix_info_plist.sh

# Step 7 (optional): Secure config URLs
./scripts/07_fix_config_urls.sh
```

## Set a custom game location

If your game is in a non-standard location, set the `GAME_APP` variable:

```bash
GAME_APP="/path/to/Worms W.M.D.app" ./fix_worms_wmd.sh
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

### Restore manually

```bash
# Find your backup
ls ~/Documents/WormsWMD-Backup-*

# Restore (replace YYYYMMDD-HHMMSS with your backup timestamp)
BACKUP_DIR=~/Documents/WormsWMD-Backup-YYYYMMDD-HHMMSS
GAME_APP="$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"

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
  cp "$BACKUP_DIR/DataOSX/"* "$GAME_APP/Contents/Resources/DataOSX/" 2>/dev/null || true
fi
```
