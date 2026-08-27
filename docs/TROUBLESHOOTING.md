# Troubleshooting

## Easiest support path

If you are not comfortable with Terminal:

1. Double-click `Worms W.M.D Fix.command`.
2. Choose option 3 to check whether the game is ready to launch.
3. If something fails, choose option 5 to create a support bundle on the
   Desktop.
4. Attach that support bundle to a GitHub issue:
   https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues

## First: Run pre-flight check

Before troubleshooting specific issues, run the pre-flight check to verify your system:

```bash
./tools/preflight_check.sh
```

This will identify common problems with:
- macOS version and Rosetta 2 status
- Game installation and fix status
- Runtime dependencies
- Optional public Team17, Steam, and GOG page reachability

Use `--verbose` for detailed output or `--quick` to skip public endpoint
checks. These checks are diagnostic only; they are not required to apply the
fix and do not prove multiplayer service health.

## Install Fix.command won't run

Gatekeeper blocks `.command` files downloaded from the internet. Try these options:

1. **Right-click method:**
   - Right-click `Worms W.M.D Fix.command` or `Install Fix.command` → select **Open** → select **Open** again in the dialog

2. **"Insufficient Privileges" or permission denied:**
   ```bash
   chmod +x ~/Downloads/WormsWMD-macOS-Fix-*/Worms\ W.M.D\ Fix.command
   chmod +x ~/Downloads/Install\ Fix.command
   ```
   Then double-click the file again. The exact folder name may vary depending
   on the release version.

3. **Remove quarantine flag:**
   ```bash
   xattr -d com.apple.quarantine ~/Downloads/WormsWMD-macOS-Fix-*/Worms\ W.M.D\ Fix.command
   xattr -d com.apple.quarantine ~/Downloads/Install\ Fix.command
   ```
   Then double-click the file.

4. **Run from Terminal:**
   ```bash
   bash ~/Downloads/WormsWMD-macOS-Fix-*/Worms\ W.M.D\ Fix.command
   bash ~/Downloads/Install\ Fix.command
   ```

5. **Use the one-liner instead:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.7.6/install.sh | bash
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

1. Repair or verify the game files in your store client:
   - Right-click **Worms W.M.D** → **Properties** → **Local Files** → **Verify integrity of game files**
   - For GOG Galaxy, use **Manage installation** → **Verify / Repair**
   - Store repair does not remove extra files from prior fixes
   - Re-run the fix script after verification
2. Check that the fix was applied:
   ```bash
   ./fix_worms_wmd.sh --verify
   ```
3. If verification says `AGL stub not found` or diagnostics say
   `AGL stub NOT installed`, run the launcher option `1` again. If it still
   fails, choose launcher option `5` and attach the support bundle to a GitHub
   issue.
4. If backup creation reports a symlink or manifest error for
   `AGL.framework`, update to the latest fixer and run option `1` again. The
   current fixer repairs stale AGL framework links from older repeated installs
   before validating the backup.
5. Check crash logs:
   - Open **Console.app**
   - Look for entries related to "Worms" in **Crash Reports**
6. Try a clean install:
   - Restore original files: `./fix_worms_wmd.sh --restore`
   - Uninstall the game in Steam or GOG Galaxy
   - Reinstall the game
   - Re-run the fix

## "Library not loaded" errors on launch

Run the verification script to identify missing dependencies:

```bash
./scripts/05_verify_installation.sh
```

The verifier resolves `@rpath` through the executable's Mach-O `LC_RPATH`
commands. A bundled resolved dependency is valid, and a missing weak-load
dependency is reported as an optional warning. A required unresolved dependency
still fails. Direct token paths that escape `Contents`, relative install names,
and unreadable required Mach-O architectures also fail. Run `--verbose` to show
the resolved bundle-relative target:

```bash
./scripts/05_verify_installation.sh --verbose
```

When Steam and GOG are both installed, use the friendly launcher so option 5
can retain the selected installation. For direct diagnostics, set the target:

```bash
GAME_APP="/Applications/Games/Worms W.M.D.app" ./tools/collect_diagnostics.sh --bundle
```

## Logging and debugging

The fix writes logs to `~/Library/Logs/WormsWMD-Fix/` by default.

To specify a custom log file under `~/Library/Logs`:

```bash
./fix_worms_wmd.sh --log-file ~/Library/Logs/WormsWMD-Fix/worms-fix.log
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

On macOS 15.x, keyboard input buffering or lag may be caused by the original Qt 5.3.2 runtime rather than Apple Silicon alone. The Qt 5.15 refresh has been reported to resolve this on macOS 15.7.3. Run `./fix_worms_wmd.sh --dry-run` first, then apply the fix if the preview looks correct for your install.

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

On macOS 27 Golden Gate, Rosetta may need to be installed again after
upgrading. Run the install command above, then open `Worms W.M.D Fix.command`
and choose option 3. If it still reports that Rosetta is unavailable, choose
option 5 to create a support bundle.

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
./tools/collect_diagnostics.sh --bundle
```

Use `--bundle` when opening a community issue. It creates a sanitized support
archive on your Desktop with diagnostics, macOS version, Rosetta package
version when available, x86_64 execution status, sanitized installer history,
runtime invariant status, Qt package verification details, backup integrity
status, and backup manifests when available. Do not upload raw `.log` or
`.trace` files unless you have reviewed and redacted account names, private
paths, tokens, and private config values.
