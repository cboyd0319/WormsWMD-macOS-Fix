# Security

This document defines the security boundaries of the Worms W.M.D macOS fix.
Detailed installer invariants live in
[`docs/design/runtime-contracts.md`](docs/design/runtime-contracts.md); player
download guidance lives in [`docs/TRUST.md`](docs/TRUST.md).

## Security posture at a glance

| Area | State | Primary control |
| --- | --- | --- |
| Privilege | Pass | Runs as the current user; no `sudo`, SUID, or system-wide writes |
| Game mutation | Pass | Validated app boundary, verified backup, transactional rollback |
| Downloads | Pass | HTTPS plus immutable refs or SHA-256 verification for executable payloads |
| Release integrity | Pass | Zip checksum, build attestation, draft-first publication, immutable future releases |
| Release SBOM | Ready | CycloneDX 1.6 plus SBOM attestation begins with the next tagged release |
| CI security | Pass | Full-SHA allowlisted Actions, least privilege, required Zizmor, CodeQL |
| New secret prevention | Pass | Enforced staged Kingfisher, required current-tree scan, GitHub push protection |
| Support privacy | Pass | Sanitized reports; no raw logs, game binaries, saves, or private configs |

Last reviewed: 2026-08-27.

## Threat model

### Controls provided

| Threat | Mitigation |
| --- | --- |
| Command injection | No `eval` on user input; shell boundaries quote and validate paths and values |
| Path traversal | Archive and tree checks reject absolute, parent, control, alias, and duplicate paths |
| Archive exhaustion | Python 3.9+ inspector caps compressed/expanded bytes, members, per-member size, and ratio before extraction |
| Symlink/hardlink escape | Mutable trees must remain inside the selected app and reject unsafe links |
| Partial or wrong-target restore | Backups are verified, app/storefront-bound, staged, and checked after restore |
| Malicious executable download | Release/Qt payloads use checksums, immutable refs, provenance, and attestations |
| CI workflow compromise | Full-SHA Action policy, selected-action allowlist, job-scoped tokens, CODEOWNERS |
| New committed secrets | Local staged scan, required current-tree scan, secret scanning, push protection |
| Diagnostic data exposure | Support bundles sanitize text and omit raw/private/game/save content |

### Assumptions and exclusions

- The user's macOS account, GitHub, Apple update services, and approved upstream
  package hosts are not already compromised.
- The project does not control or rotate Team17 credentials embedded in the
  original game or found in old vendor-report history.
- Git hooks can be bypassed with `--no-verify`; required CI and GitHub push
  protection are the server-side backstop.
- The fix cannot provide Apple Developer ID notarization for Team17's game.

## Runtime boundaries

The installer may change the selected app's `Contents/Frameworks`, `PlugIns`,
`MacOS`, `_CodeSignature`, `Info.plist`, and known DataOSX/CommonData config
files. It may create these user-owned paths outside the bundle:

| Path | Purpose | Removal |
| --- | --- | --- |
| `~/Documents/WormsWMD-Backup-*/` | Original game-file backups | Manual |
| `~/Documents/WormsWMD-SaveBackups/` | Optional save backups | Manual |
| `~/Library/Logs/WormsWMD-Fix/` | Installer logs | Manual |
| `~/Library/Logs/WormsWMD/` | Launcher/crash logs | Manual |
| `~/.cache/wormswmd-fix/` | Verified Qt cache | Manual or `--force` |
| `~/Library/LaunchAgents/com.wormswmd.fix.watcher.plist` | Optional watcher | `--uninstall` |
| `${TMPDIR:-/tmp}/agl_stub_build.*/` | AGL build workspace | Automatic |
| Same-parent `.stage-*` bottle prefix | Maintainer-only Qt rebuild staging | Automatic |

The fix does not modify system directories, collect telemetry, alter `PATH` or
`DYLD_LIBRARY_PATH`, or install privileged persistence.

### Untrusted inputs

| Input | Required validation |
| --- | --- |
| `GAME_APP` | Expected executable plus contained, regular, link-safe mutable trees |
| `INSTALL_DIR` | User project path; not home/system/non-empty foreign repository |
| `INSTALL_REF` | Defaults to v1.7.6; other refs require explicit developer opt-in |
| `LOG_FILE` | Regular `.log` beneath `~/Library/Logs` |
| `QT_PREFIX` | Required Qt 5.15.x layout and explicit custom-prefix opt-in |
| Archive files | Bounded owner-only copy, external digest where available, shared profile, same-copy extraction |

The complete backup, restore, archive, Mach-O, signing, and diagnostics
contracts are maintained in
[`runtime-contracts.md`](docs/design/runtime-contracts.md).

## Network and supply-chain controls

| Purpose | Destination | Control |
| --- | --- | --- |
| Repository/bootstrap/update | `github.com`, `raw.githubusercontent.com`, `api.github.com` | HTTPS, release tag/commit pin, checksum for downloads |
| Qt runtime | Repository `dist/` or pinned commit | SHA-256, metadata, manifest, layout, links, x86_64 closure |
| Qt provenance rebuild | `formulae.brew.sh`, `ghcr.io`, approved GitHub storage | Authoritative reviewed lock, exact digest paths, bounded redirects/downloads; bearer removed cross-origin |
| Kingfisher developer/CI binary | `github.com/mongodb/kingfisher` | Fixed 2.0.0 release and per-platform SHA-256 |
| Public preflight probes | Team17, Steam, GOG pages | Optional HTTPS reachability only |
| Rosetta/Xcode tools | Apple services | macOS-managed installation |
| Release attestation | GitHub Actions OIDC/attestation services | Short-lived OIDC plus job-scoped token |

Project-owned `curl` downloads enforce HTTPS, TLS 1.2+, certificate checks,
timeouts, and bounded retries. Git, `gh`, and Apple system services own their
TLS settings; project scripts do not weaken them.

### Qt package verification

The shipped Qt archive is accepted only after verifying:

1. SHA-256 and Qt 5.15.x/x86_64 metadata.
2. Whitelisted layout and required frameworks/plugins.
3. No traversal, control paths, canonical aliases, hardlinks, special files,
   or escaping symlinks.
4. Archive/generated manifest and complete non-system Mach-O dependency closure.
5. `SOURCE_PROVENANCE.tsv`, which locks the 17 Homebrew bottle inputs, source
   hashes, formula hashes, and tap commit. SBOM generation requires its
   standalone copy to be byte-identical to the copy inside the checksummed
   archive.

The authoritative rebuild input is `packaging/qt-homebrew-lock.tsv`; the
`dist/` TSV is generated evidence. Bottle rebuilds validate the exact allowlisted
closure, GHCR digest path, archive profile, formula/version root, revision, and
bounded embedded formula metadata.
They do not execute extracted `qmake`. Output is staged beside the target and
cannot replace or clean a nonempty directory without its exact path-bound
ownership marker and the matching explicit flag.

## GitHub and CI controls

### Hosted repository settings

- `main` requires current ShellCheck, Validate Scripts, and Zizmor checks, one
  CODEOWNER review, stale-review dismissal, and conversation resolution.
- Force pushes and branch deletion are disabled. Administrator enforcement is
  deliberately off because one required review plus one maintainer would make
  normal maintenance impossible.
- Default workflow tokens are read-only and cannot approve pull requests.
- Actions are limited to GitHub-owned actions plus pinned ShellCheck and Zizmor;
  the hosted policy requires full commit SHAs.
- Every external contributor requires approval before fork workflows run.
- CodeQL scans GitHub Actions, C/C++, and Ruby on supported PRs, protected-branch
  pushes, and weekly. GitHub excludes fork PRs from default CodeQL setup.
- GitHub secret scanning, push protection, private vulnerability reporting, and
  Dependabot security updates are enabled. Enhanced partner validity and generic
  patterns require an unavailable Team/Enterprise Secret Protection plan.
- Future releases are immutable. GitHub does not retroactively lock v1.7.6.

### Cost-aware required CI

CI cancels stale runs. Cheap Ubuntu ShellCheck, harness, policy, hook, and SBOM
tests run before macOS. Runtime/unknown/empty/CI/release changes then use one
macOS job for all regressions plus AGL compilation. Allowlisted documentation,
community metadata, and agent-guidance changes report that required macOS job as
skipped-success. A failed diff/classifier always falls back to macOS.

Security/release workflows do not reuse untrusted cross-run caches. Workflow
artifacts expire after 14 days.

### Staged and CI secret scanning

Run once per clone:

```bash
./tools/install_git_hooks.sh
```

This installs checksum-pinned Kingfisher 2.0.0 beneath the local Git directory
and sets `core.hooksPath=.githooks`. The hook scans staged content and fails
closed when the scanner is missing, has another version, or differs from the
pinned per-platform executable digest. Installation defaults to a clean checkout
at the reviewed official `origin/main`; another reviewed commit requires its
exact HEAD.
`--uninstall` retains the scanner and explicit `--purge` removes only the exact
validated cache path. CI scans the current checkout in the existing Zizmor job,
sharing its Ubuntu runner.

Both modes redact findings, disable live provider validation and update checks,
exclude Git history/internals, and avoid extracting or scanning the vendored Qt
archive. The fixed Linux x64 CI asset SHA-256 is:

```text
d30d71f82e25e8c024f98cce3258c90e17b5be31d0fdb6f30b438d2fac1f130b
```

## Release integrity and SBOM

For future tags, the release workflow:

1. Validates the harness, shell syntax, and Qt package.
2. Builds the zip and matching `.zip.sha256`.
3. Extracts the matching `CHANGELOG.md` section as release notes.
4. Verifies the locked Qt provenance matches the copy in the checksummed Qt
   archive, then generates deterministic CycloneDX 1.6 JSON from it.
5. Hashes the built release zip, verifies its checksum file, and uses that
   verified digest as the SBOM root hash.
6. Attests build assets and separately binds the SBOM to the zip.
7. Uploads notes/assets to a resumable draft, then publishes it immutably.
8. Refuses to overwrite any published release.

The SBOM lists the release plus the 17 Homebrew bottle components used for the
bundled Qt runtime. It records bottle/source/formula hashes and source URLs. The
flat lock proves the complete set, not internal edges, so only the
release-to-component relationship is asserted. Game files, macOS, Rosetta,
Xcode, and optional user-installed Homebrew fallbacks are outside its scope.

v1.7.6 predates SBOM publication and repository-level immutability. Its hosted
zip checksum and build attestation remain independently verifiable.

## Verification

### Verify the current release

```bash
cd ~/Downloads
shasum -a 256 -c WormsWMD-macOS-Fix-v1.7.6.zip.sha256
gh attestation verify WormsWMD-macOS-Fix-v1.7.6.zip \
  --repo cboyd0319/WormsWMD-macOS-Fix
```

Starting with the next release, also download
`WormsWMD-macOS-Fix-vX.Y.Z.cdx.json`; `gh attestation verify` on the zip returns
both its build provenance and SBOM relationship.

### Maintainer security checks

```bash
./tools/install_git_hooks.sh --check
./tools/test_git_hooks.sh
./tools/test_github_security.sh
./tools/test_ci_changed_paths.sh
./tools/test_ci_change_classification.sh
python3 tools/test_generate_sbom.py
/usr/bin/python3 tools/test_archive_inspector.py
ruby tools/test_fetch_qt_homebrew_bottles.rb
./tools/validate_harness.sh
actionlint .github/workflows/*.yml
zizmor --persona=pedantic --no-ignores --no-progress .github
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" \
  "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
```

Runtime verification remains:

```bash
./fix_worms_wmd.sh --dry-run
./fix_worms_wmd.sh --verify
./tools/preflight_check.sh
```

## Known limitations

| Limitation | Current mitigation |
| --- | --- |
| Qt package is not independently signed | Locked inputs, checksums, manifests, Mach-O closure, release attestation |
| Archive inspection needs Python 3.9+ | macOS 26 Apple Command Line Tools provide it; mutating archive operations fail with install/update guidance |
| Update downloader verifies checksum but not attestation | Users can run `gh attestation verify` on the downloaded zip |
| Modified game uses ad-hoc signing | Strict signature verification occurs inside rollback boundary |
| Legacy backups lack complete identity/integrity | Explicit warning; ambiguous multi-install restore refused |
| Team17-controlled credentials exist in the game/old report history | Current repo is redacted; project does not validate, rotate, or gate on vendor values |
| Local hooks can be absent or bypassed | Required current-tree Kingfisher plus GitHub push protection |
| Admin branch bypass remains enabled | Required checks/review still apply normally; second trusted reviewer needed before enforcement |
| v1.7.6 is mutable and has no SBOM | Existing checksum/build attestation; future releases immutable with SBOM |
| First hosted SBOM publication is not yet exercised | Generator passed official CycloneDX schema and zip-root-hash tests; next tag is final end-to-end proof |

## Reporting a vulnerability

Do not open a public issue containing vulnerabilities, credentials, or exploit
details. Submit a [private GitHub vulnerability
report](https://github.com/cboyd0319/WormsWMD-macOS-Fix/security/advisories/new).
Reports should include impact, reproduction steps, affected versions, and a
suggested mitigation when available. An acknowledgement is expected within 48
hours.
