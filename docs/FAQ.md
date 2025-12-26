# FAQ

## General

**Q: Does this fix work on macOS 15 (Sequoia) or earlier?**

You probably don't need it. This fix targets macOS 26 (Tahoe) where Apple removed AGL.

**Q: Does this fix work for the GOG version?**

Yes. The fix modifies the app bundle, which is the same for Steam and GOG. Set `GAME_APP` to your GOG installation path.

**Q: Is this fix safe?**

Yes. The fix only modifies files inside the game's app bundle, creates a backup first, and doesn't require `sudo`. See `SECURITY.md` for details.

**Q: Can I undo this fix?**

Yes. Run `./fix_worms_wmd.sh --restore` or verify game files in Steam to restore the original files.

## Technical

**Q: Does this fix require Homebrew?**

No. The fix downloads pre-built Qt frameworks automatically. Homebrew is a fallback if the download fails.

**Q: Why Qt 5.15 instead of Qt 6?**

Qt 5.15 preserves binary compatibility with the Qt 5.3 APIs the game uses.

**Q: What does the AGL stub do?**

It provides empty AGL functions so the game can launch. Qt 5.15 doesn't use AGL at runtime.

**Q: Is Apple Silicon native support possible?**

Not without source code. Team17 would need to ship a universal binary.

## Performance

**Q: Is performance worse on Apple Silicon compared to Intel?**

Rosetta adds overhead, but most systems still run the game smoothly.

**Q: The game runs slowly on first launch after the fix. Is this normal?**

Yes. Rosetta translates x86_64 code on first run and caches it. Subsequent launches are faster.

**Q: Are there any graphics settings I should change?**

Defaults should work. If you see issues, lower the resolution or disable effects. The diagnostic launcher supports `--safe-mode`.

## Troubleshooting

**Q: I get "app is damaged" or Gatekeeper warnings. What do I do?**

Right-click the app and select **Open**, then select **Open** again. The fix also applies ad-hoc signing and clears quarantine flags.

**Q: Multiplayer and online features don't work. Is this related to the fix?**

The fix doesn't modify networking. Check Team17 or Steam community status for server issues.

**Q: My controller doesn't work. Can the fix help?**

Run `./tools/controller_helper.sh` to check controller connectivity and get configuration tips.
