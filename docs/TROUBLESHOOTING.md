# Troubleshooting

## First: Run pre-flight check

Before troubleshooting specific issues, run the pre-flight check to verify your system:

```bash
./tools/preflight_check.sh
```

This will identify common problems with:
- macOS version and Rosetta 2 status
- Game installation and fix status
- Runtime dependencies
- Network connectivity

Use `--verbose` for detailed output or `--quick` to skip network checks.

## Install Fix.command won't run

Gatekeeper blocks `.command` files downloaded from the internet. Try these options:

1. **Right-click method:**
   - Right-click `Install Fix.command` → select **Open** → select **Open** again in the dialog

2. **Remove quarantine flag:**
   ```bash
   xattr -d com.apple.quarantine ~/Downloads/Install\ Fix.command
   ```
   Then double-click the file.

3. **Run from Terminal:**
   ```bash
   bash ~/Downloads/Install\ Fix.command
   ```

4. **Use the one-liner instead:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
   ```
   Requires `git` (installed by Xcode Command Line Tools).

## Small window that won't resize

The game window may appear very small after applying the fix. This happens because old Qt 5.3 window geometry settings are incompatible with Qt 5.15.

**The fix script now resets this automatically**, but if you still experience this issue:

1. **Reset window geometry manually:**
   ```bash
   defaults delete "com.team17.Worms W.M.D" "QtSystem_GameWindow.geometry"
   defaults delete "com.team17.Worms W.M.D" "QtSystem_GameWindow.windowState"
   ```
   Then relaunch the game.

2. **If the above doesn't work**, try changing resolution in-game:
   - Press **Esc** or go to **Help & Options** → **Settings** → **Display**
   - Change **Resolution** to your preferred size
   - Select **Apply** and restart the game

## Game still shows a black screen

1. Verify game files in Steam (note: this does not remove extra files from prior fixes):
   - Right-click **Worms W.M.D** → **Properties** → **Local Files** → **Verify integrity of game files**
   - Re-run the fix script after verification
2. Check that the fix was applied:
   ```bash
   ./fix_worms_wmd.sh --verify
   ```
3. Check crash logs:
   - Open **Console.app**
   - Look for entries related to "Worms" in **Crash Reports**
4. Try a clean install:
   - Restore original files: `./fix_worms_wmd.sh --restore`
   - Uninstall the game in Steam
   - Reinstall the game
   - Re-run the fix

## "Library not loaded" errors on launch

Run the verification script to identify missing dependencies:

```bash
./scripts/05_verify_installation.sh
```

## Logging and debugging

The fix writes logs to `~/Library/Logs/WormsWMD-Fix/` by default.

To specify a custom log file:

```bash
./fix_worms_wmd.sh --log-file /path/to/log.txt
```

For more detail:

```bash
./fix_worms_wmd.sh --debug
./fix_worms_wmd.sh --verify --verbose
```

## Diagnostic game launcher

Launch the game with extra logging:

```bash
./tools/launch_worms.sh --log
./tools/launch_worms.sh --safe-mode --log
./tools/launch_worms.sh --qt-debug --opengl-debug --log --verbose
```

Logs are saved to `~/Library/Logs/WormsWMD/`.

## Performance issues on Apple Silicon

If you experience input lag, stuttering, or slow performance:

1. Disable V-Sync (often helps):
   - In-game: **Help & Options** → **Settings** → disable **Vertical Sync**
2. Use windowed mode:
   - In-game: **Help & Options** → **Settings** → **Display**
   - Change **Fullscreen** to **Windowed**
   - Set your desired resolution
   - Don't expand to fit the screen
3. Disable Steam Input (for controller issues):
   - **Steam** → **Settings** → **Controller**
   - Disable all **Enable Steam Input for...** options
   - Restart Steam and the game

## Rosetta 2 issues

Check whether Rosetta is available:

```bash
/usr/bin/arch -x86_64 /usr/bin/true && echo "Rosetta is available" || echo "Rosetta is NOT available"
```

To install or reinstall Rosetta:

```bash
softwareupdate --install-rosetta --agree-to-license
```

## Pre-built Qt download failed (Homebrew fallback)

If the automatic Qt download fails, install Intel Homebrew as a fallback:

```bash
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
arch -x86_64 /usr/local/bin/brew install qt@5
```

If you see permission errors:

```bash
sudo mkdir -p /usr/local/var/homebrew/locks /usr/local/etc /usr/local/Frameworks
sudo chown -R $(whoami) /usr/local/var /usr/local/etc /usr/local/Frameworks
```

## Collect diagnostics for bug reports

To gather system information for a bug report:

```bash
./tools/collect_diagnostics.sh
./tools/collect_diagnostics.sh --output ~/Desktop/worms-diagnostics.txt
./tools/collect_diagnostics.sh --copy
./tools/collect_diagnostics.sh --full --output ~/Desktop/worms-full-diagnostics.txt
```
