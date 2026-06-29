# Support

If you are helping someone who is not technical, send them the release zip and
ask them to open `README_FIRST.txt`. The intended path is:

1. Unzip the release.
2. Double-click `Worms W.M.D Fix.command`.
3. Choose option 1.
4. If it fails, choose option 5 and attach the Desktop support bundle to an
   issue.

If the person wants to verify the download first, ask them to download the
matching `.zip.sha256` file from the same release and run:

```bash
shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.2.zip.sha256
```

## What to include in an issue

Use the installation failure template for failed apply, verify, or restore runs.
Use the bug report template when the fix installs but the game or a repo tool
still behaves incorrectly.

- macOS version and Mac model, if you know them.
- Steam or GOG install.
- What happened when choosing option 1.
- The support bundle from option 5.

Do not paste Steam account tokens, private config files, save archives, or game
binaries into a public issue. The support bundle is designed to include
sanitized diagnostics, macOS version, Rosetta package version when available,
x86_64 execution status, sanitized installer history, runtime invariant status,
Qt package status, backup integrity status, and backup manifests only. Avoid
uploading raw `.log` or `.trace` files; use the support bundle unless a
maintainer specifically asks for a reviewed, redacted excerpt.

## Quick fixes

If macOS blocks the launcher, right-click `Worms W.M.D Fix.command`, choose
**Open**, then choose **Open** again.

If the game was updated or verified through Steam, run the launcher again and
choose option 1. Steam verification can replace fixed game-bundle files.

If you need to undo the fix, run the launcher and choose option 4.
