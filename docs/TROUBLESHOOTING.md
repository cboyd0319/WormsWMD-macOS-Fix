# Troubleshooting

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

## Small window on first launch

The game window may appear very small on the first launch after applying the fix. This is normal and resolves on subsequent launches.

If the window stays small:
1. Press **Esc** or go to **Help & Options** → **Settings** → **Display**
2. Change **Resolution** to your preferred size
3. Select **Apply** and restart the game

## Game still shows a black screen

1. Verify game files in Steam:
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
   - Verify game files in Steam
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

1. Disable V-Sync (most effective):
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
