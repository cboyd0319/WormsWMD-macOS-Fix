# Zero-Technical Release Experience

Status: Completed

## Problem

Community players reported that the fix is too confusing. The current project
works for technical users, but a Steam-forum player with no Terminal experience
has to understand `.command` files, GitHub downloads, command-line flags, logs,
and support bundle commands before they can recover from trouble.

## Scope and non-goals

In scope:

- Add a friendly double-click launcher that presents plain-language actions for
  applying, previewing, verifying, restoring, and collecting support data.
- Keep the existing `fix_worms_wmd.sh` orchestrator as the canonical fix engine.
- Add release-bundle tooling so maintainers can publish a ready-to-download zip.
- Add GitHub release automation around the existing CI checks.
- Update user docs, support docs, Steam-forum copy, attribution policy, and
  agent instructions so the release path is accurate.
- Add original lightweight visual identity assets that make the project feel
  more approachable without shipping official game art.

Non-goals:

- Do not bundle official Team17 or Worms artwork unless explicit permission or a
  redistributable license is documented in the repo.
- Do not copy sample assets from unrelated projects unless their exact license
  and attribution are committed with the asset.
- Do not replace the Qt archive in `dist/` as part of this UX pass.
- Do not add privileged installers, system-wide writes, telemetry, or account
  collection.

## Constraints and risks

- `GAME_APP`, `INSTALL_DIR`, `LOG_FILE`, and `QT_PREFIX` remain untrusted input;
  all paths must be quoted and spaces in `Worms W.M.D.app` must be preserved.
- The friendly launcher must be Bash 3.2 compatible because it runs on macOS.
- The release bundle must avoid `.git`, build outputs, downloaded examples, and
  user data.
- Official game screenshots and press assets may be useful for human reference,
  but the repo should treat them as non-redistributable unless Team17 grants
  permission.
- The public tone should be fun without looking like an official Team17 product.

## Milestones

- [x] Milestone 1: Add `Worms W.M.D Fix.command` and route existing bootstrap
  entrypoints through it when running interactively.
- [x] Milestone 2: Add `tools/build_release_bundle.sh`, generated manifest
  support, zip/checksum output, and CI/release workflow coverage.
- [x] Milestone 3: Add `README_FIRST.txt`, `SUPPORT.md`, `STEAM_POST.md`,
  `ATTRIBUTIONS.md`, and original visual assets.
- [x] Milestone 4: Update `README.md`, `docs/INSTALL.md`,
  `docs/TROUBLESHOOTING.md`, `docs/TOOLS.md`, `docs/TECHNICAL.md`,
  `docs/README.md`, `docs/design/runtime-contracts.md`, `CHANGELOG.md`, and
  `AGENTS.md` to match the new behavior.
- [x] Milestone 5: Run the full shell, docs, package, and compile validation
  set; record results before committing.

## Verification

Run these commands before completion:

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
./scripts/download_qt_frameworks.sh --check
./tools/package_qt_frameworks.sh --help
./tools/collect_diagnostics.sh --help
./tools/backup_saves.sh --help
./tools/build_release_bundle.sh --version local-smoke --skip-zip
./tools/build_release_bundle.sh --version local-smoke
unzip -l build/release/WormsWMD-macOS-Fix-local-smoke.zip | head
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
git diff --check
```

## Progress

- 2026-04-29: Started plan after user approved making the fix easier and more
  fun for zero-technical players.
- 2026-04-29: Added the friendly launcher, updated bootstrap behavior, created
  release-bundle tooling, added original visual assets, and refreshed the
  user/support/maintainer docs around the one-zip flow.
- 2026-04-29: Built a local smoke release. The first zip included macOS metadata
  sidecars, so the builder now prefers `zip -X` to keep release archives tidy.
- 2026-04-29: Expanded the README's deliberately loud retro treatment with more
  original visuals while keeping the quick-start answer at the very top.

## Surprises & Discoveries

- A referenced local example README uses a highly playful visual style. Useful
  ideas are the clear "big button" instructions, badges, and personality; the
  implementation here should stay simpler and public-project appropriate.
- WebPets sample assets were not copied because only one inspected asset license
  was clearly documented, and it was not a good fit for redistributing in this
  project.
- Team17 has official game/media and press/creator pages, but the legal terms
  reserve game artwork and characters. The repo should not bundle official art
  without direct permission.
- The currently verified local Qt package remains 5.15.18. This pass preserves
  the documented 5.15.19 packaging path, but does not invent a 5.15.19 binary
  without a compatible x86_64 artifact and checksum.

## Decision Log

- Use a menu-driven `.command` launcher instead of a native app. It is easy to
  audit, works with the current shell scripts, and avoids signing/notarization
  overhead for a community project.
- Keep `fix_worms_wmd.sh` as the canonical engine. The new launcher is a
  friendly wrapper, not a second installer implementation.
- Ship original text/SVG branding only. Candidate official or third-party art
  can be revisited later if the license is clear and attribution is committed.
- Build release zips from the repository contents with a generated manifest and
  SHA-256 checksum so users can download one package instead of assembling files
  from GitHub.

## Outcomes & Retrospective

- Shipped a double-click menu wrapper for apply, preview, verify, restore,
  support bundle creation, and simple help.
- Existing bootstrap entrypoints now open the friendly menu when interactive;
  scripted use still forwards flags to `fix_worms_wmd.sh`.
- Added release bundle generation with `RELEASE_INFO.txt`,
  `RELEASE_MANIFEST.tsv`, zip creation, and SHA-256 checksum output.
- Added GitHub release workflow coverage and CI smoke coverage for release
  bundle creation.
- Added `README_FIRST.txt`, normal-person support guidance, Steam-forum copy,
  attribution policy, and original SVG branding.
- Validation passed locally with harness validation, ShellCheck, Bash syntax
  checks, fix dry-run, Qt package availability check, tool help checks, release
  folder/zip smoke builds, metadata-free zip listing, AGL stub compilation, and
  `git diff --check`.
- GitHub CLI checks returned no open issues and no open pull requests at the
  time of validation.
- The final pushed commit hash is reported in the session close-out after Git
  creates it.
