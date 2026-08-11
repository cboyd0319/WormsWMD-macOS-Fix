# Trust And Safety

This project should not require blind trust. It is a small, auditable community
fix that runs as your normal macOS user, modifies only the Worms W.M.D app
bundle, and gives you a preview and restore path.

## Best path for most players

1. Download the latest release zip from:
   https://github.com/cboyd0319/WormsWMD-macOS-Fix/releases/latest
2. Download the matching `.zip.sha256` file.
3. Verify the zip:

   ```bash
   cd ~/Downloads
   shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.5.zip.sha256
   ```

4. Unzip it and run `Worms W.M.D Fix.command`.
5. Choose option `2` first if you want to preview changes before applying them.

## Stronger provenance check

Release zips are built by the repository's GitHub Actions release workflow. The
workflow publishes artifact attestations so you can verify that a release asset
came from this repository's build process:

```bash
gh attestation verify WormsWMD-macOS-Fix-v1.7.5.zip --repo cboyd0319/WormsWMD-macOS-Fix
```

The checksum proves the downloaded zip matches the release asset. The
attestation links the release asset to the GitHub Actions workflow that built
it.

## What makes this lower risk

- No `sudo`, administrator password, kernel extension, or system-wide installer.
- The default launcher has a dry-run preview option before applying changes.
- Original game files are backed up before replacement and can be restored.
- Pre-built Qt packages are checked with SHA-256, metadata, safe archive paths,
  generated or archive-provided manifests, and x86_64 architecture validation
  before use.
- Support bundles are designed to exclude game binaries, save archives, and
  private account tokens.
- Maintainer review is required for trust-sensitive files through
  `.github/CODEOWNERS`.
- GitHub Actions validates shell syntax, ShellCheck, harness docs, release
  packaging, and the AGL stub compile.

## What it can still do

The fix needs write access to the Worms W.M.D app bundle because it replaces the
runtime files that stop the game from launching. That means you should only run
code from a release you meant to download, and you should use option `2` first
if you want to see the planned changes.

## Files worth reviewing

- `Worms W.M.D Fix.command` is the double-click launcher.
- `fix_worms_wmd.sh` is the main fix script.
- `install.sh` is only the optional terminal/bootstrap installer.
- `SECURITY.md` documents the threat model and audit checklist.
- `.github/workflows/` shows the CI and release workflow.
