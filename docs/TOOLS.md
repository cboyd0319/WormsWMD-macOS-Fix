# Tools

The `tools/` directory includes helper utilities for backups, diagnostics, and launch options.

## Save game backup

Back up and restore your save games, settings, and replays:

```bash
./tools/backup_saves.sh
./tools/backup_saves.sh --list
./tools/backup_saves.sh --restore
```

## Steam update watcher

Steam's **Verify integrity of game files** overwrites the fix. Use the watcher to detect when this happens:

```bash
./tools/watch_for_updates.sh --check
./tools/watch_for_updates.sh --daemon &
./tools/watch_for_updates.sh --install
./tools/watch_for_updates.sh --uninstall
```

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

## Controller helper

Diagnose controller connectivity and get configuration tips:

```bash
./tools/controller_helper.sh
./tools/controller_helper.sh --info
```

## Diagnostics collector

Gather system information for bug reports:

```bash
./tools/collect_diagnostics.sh
./tools/collect_diagnostics.sh --output ~/Desktop/worms-diagnostics.txt
./tools/collect_diagnostics.sh --copy
./tools/collect_diagnostics.sh --full --output ~/Desktop/worms-full-diagnostics.txt
```

## Enhanced launcher

Launch the game with extra logging and debug options:

```bash
./tools/launch_worms.sh --log
./tools/launch_worms.sh --safe-mode --log
./tools/launch_worms.sh --qt-debug --opengl-debug --log --verbose
```

Crash reports are saved to `~/Library/Logs/WormsWMD/crashes/`.
