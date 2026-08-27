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
   shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.6.zip.sha256
   ```

4. Unzip it and run `Worms W.M.D Fix.command`.
5. Choose option `2` first if you want to preview changes before applying them.

## Stronger provenance check

Release zips are built by the repository's GitHub Actions release workflow. The
workflow publishes artifact attestations so you can verify that a release asset
came from this repository's build process:

```bash
gh attestation verify WormsWMD-macOS-Fix-v1.7.6.zip --repo cboyd0319/WormsWMD-macOS-Fix
```

The checksum proves the downloaded zip matches the release asset. The
attestation links the release asset to the GitHub Actions workflow that built
it.

## What makes this lower risk

- No `sudo`, administrator password, kernel extension, or system-wide installer.
- The default launcher has a dry-run preview option before applying changes.
- Covered original game files, including the complete `Contents/MacOS` tree and
  existing signature resources, are backed up before replacement. New backups
  remain hidden until verification and are bound to their canonical source app
  and Steam or GOG storefront before restore.
- Pre-built Qt packages are checked with SHA-256, metadata, safe archive paths,
  generated or archive-provided manifests, and x86_64 architecture validation
  before use.
- Support bundles are designed to exclude game binaries, save archives, and
  private account tokens.
- Maintainer review is required for trust-sensitive files through
  `.github/CODEOWNERS`.
- GitHub Actions validates shell syntax, ShellCheck, harness docs, release
  packaging, and the AGL stub compile.
- GitHub workflows use job-scoped permissions, bounded execution, disabled
  checkout credential persistence, immutable Action SHAs, and a seven-day
  update cooldown.
- A required Zizmor job and the local GitHub policy regression validate
  workflow changes before they reach release automation.
- A repository-local pre-commit hook runs checksum-pinned Kingfisher 2.0.0 on
  staged changes. Required CI scans the current tree as a backstop; neither mode
  traverses Git history or sends candidates to providers for live validation.
- GitHub also enforces full-SHA Actions, an allowlist limited to GitHub-owned
  actions plus ShellCheck and Zizmor, approval for every external contributor,
  and CodeQL scanning for Actions, C/C++, and Ruby.
- Release publication uploads assets and notes to a draft first, refuses to
  replace a published release, and publishes only after checksum assets and
  attestations exist. Repository-level immutability protects future published
  releases; v1.7.6 predates that GitHub setting.
- Tagged releases publish a deterministic CycloneDX SBOM for the complete
  checksum-locked Qt bottle inventory. GitHub's SBOM attestation binds that
  inventory to the release zip.

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
