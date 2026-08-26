# FAQ

## General

**Q: Does this fix work on macOS 15 (Sequoia) or earlier?**

This fix targets macOS 26 Tahoe and later, where Apple removed AGL. On macOS
27 Golden Gate, Apple Silicon Macs also need Rosetta installed because Worms
W.M.D is an older Intel Mac game. Earlier macOS versions typically don't need
the AGL fix unless you're seeing the same black-screen symptoms.

There is also a confirmed report that applying the Qt 5.15 refresh resolved keyboard input buffering/lag on macOS 15.7.3 (Sequoia). Use `Worms W.M.D Fix.command` option 2 first if you want to preview the changes, or run `./fix_worms_wmd.sh --dry-run` from Terminal.

**Q: Does this fix work for the GOG version?**

The fix operates on the macOS app bundle. Common GOG locations, including
`$HOME/GOG Games`, are auto-detected by the installer, diagnostics, and
preflight checks. Set `GAME_APP` only if your GOG install is in a non-standard
location.

**Q: Is this fix safe?**

Yes. The fix only modifies files inside the game's app bundle, creates a
backup first, verifies pre-built Qt packages with checksums plus archive or
generated cache manifests, and doesn't require `sudo`. Release zips also
include checksum and provenance verification. See `SECURITY.md` and
`docs/TRUST.md` for details.

**Q: Can I undo this fix?**

Yes. Use `Worms W.M.D Fix.command` option 4, run
`./fix_worms_wmd.sh --restore`, or uninstall/reinstall the game. New backups
include `BACKUP_MANIFEST.tsv` and `BACKUP_METADATA.tsv`, which restore verifies
and matches to the selected Steam or GOG app before copying files
back. Steam "Verify integrity" does not remove extra files from prior fixes.

## Technical

**Q: Does this fix require Homebrew?**

No. The fix downloads pre-built Qt frameworks automatically. Homebrew is a fallback if the download fails.

**Q: Does this ship Qt 5.15.19?**

Yes. As of 2026-06-18, `dist/` ships Qt 5.15.19 as an x86_64 runtime archive
with a matching checksum and Homebrew bottle provenance lock.

**Q: Why Qt 5.15 instead of Qt 6?**

Qt 5.15 preserves binary compatibility with the Qt 5.3 APIs the game uses.

**Q: What does the AGL stub do?**

It provides empty AGL functions so the game can launch. Qt 5.15 doesn't use AGL at runtime.

**Q: Is Apple Silicon native support possible?**

Not without source code. Team17 would need to ship a universal binary.

**Q: What changes on macOS 27 Golden Gate?**

Apple says Rosetta remains available through macOS 27, then changes in macOS
28. On this macOS 27 beta laptop, Rosetta had to be installed again after the
upgrade. This fix can still update the game bundle, but Worms needs Rosetta
before it can launch on Apple Silicon.

Apple's current Rosetta support article is here:
https://support.apple.com/102527

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

The fix doesn't modify networking. Check Team17, Steam, or GOG community status
for server issues, depending on where you bought the game.

**Q: My controller doesn't work. Can the fix help?**

Run `./tools/controller_helper.sh` to check controller connectivity and get configuration tips.

**Q: How can I verify my system is ready before launching?**

Use `Worms W.M.D Fix.command` option 3 for the quick launch-readiness check.
For a deeper system check, run `./tools/preflight_check.sh` to check system
requirements, Rosetta status, fix status, and optional public Team17, Steam,
and GOG page reachability.
