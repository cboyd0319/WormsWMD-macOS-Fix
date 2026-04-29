# FAQ

## General

**Q: Does this fix work on macOS 15 (Sequoia) or earlier?**

This fix targets macOS 26 (Tahoe) where Apple removed AGL. Earlier macOS versions typically don't need it unless you're seeing the same black-screen symptoms.

There is also a confirmed report that applying the Qt 5.15 refresh resolved keyboard input buffering/lag on macOS 15.7.3 (Sequoia). Use `Worms W.M.D Fix.command` option 2 first if you want to preview the changes, or run `./fix_worms_wmd.sh --dry-run` from Terminal.

**Q: Does this fix work for the GOG version?**

The fix operates on the macOS app bundle. If your GOG install uses the same app bundle layout, it should work. Set `GAME_APP` to your GOG installation path.

**Q: Is this fix safe?**

Yes. The fix only modifies files inside the game's app bundle, creates a
backup first, verifies pre-built Qt packages with checksums and manifests, and
doesn't require `sudo`. Release zips also include checksum and provenance
verification. See `SECURITY.md` and `docs/TRUST.md` for details.

**Q: Can I undo this fix?**

Yes. Use `Worms W.M.D Fix.command` option 4, run
`./fix_worms_wmd.sh --restore`, or uninstall/reinstall the game. New backups
include `BACKUP_MANIFEST.tsv`, which restore verifies before copying files
back. Steam "Verify integrity" does not remove extra files from prior fixes.

## Technical

**Q: Does this fix require Homebrew?**

No. The fix downloads pre-built Qt frameworks automatically. Homebrew is a fallback if the download fails.

**Q: Does this ship Qt 5.15.19?**

The scripts can package and consume a supplied compatible Qt 5.15.19 x86_64
prefix, but this repository only ships the Qt archive that is present in
`dist/` with its matching checksum.

**Q: Why Qt 5.15 instead of Qt 6?**

Qt 5.15 preserves binary compatibility with the Qt 5.3 APIs the game uses.

**Q: What does the AGL stub do?**

It provides empty AGL functions so the game can launch. Qt 5.15 doesn't use AGL at runtime.

**Q: Is Apple Silicon native support possible?**

Not without source code. Team17 would need to ship a universal binary.

## Performance

**Q: Is performance worse on Apple Silicon compared to Intel?**

Rosetta adds overhead; actual performance varies by system.

**Q: The game runs slowly on first launch after the fix. Is this normal?**

Yes. Rosetta translates x86_64 code on first run and caches it. Subsequent launches are faster.

**Q: Are there any graphics settings I should change?**

Defaults often work. If you see issues, lower the resolution or disable effects. The diagnostic launcher supports `--safe-mode`.

## Troubleshooting

**Q: I get "app is damaged" or Gatekeeper warnings. What do I do?**

Right-click the app and select **Open**, then select **Open** again. The fix also applies ad-hoc signing and clears quarantine flags.

**Q: Multiplayer and online features don't work. Is this related to the fix?**

The fix doesn't modify networking. Check Team17 or Steam community status for server issues.

**Q: My controller doesn't work. Can the fix help?**

Run `./tools/controller_helper.sh` to check controller connectivity and get configuration tips.

**Q: How can I verify my system is ready before launching?**

Use `Worms W.M.D Fix.command` option 3 for the quick fix-status check. For a
deeper system check, run `./tools/preflight_check.sh` to check system
requirements, Rosetta 2 status, fix status, and network connectivity.
