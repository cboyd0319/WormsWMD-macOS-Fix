# Agent Session Runbook

Use this runbook when starting, validating, handing off, or closing work in this
repository.

## Start A Session

```bash
git status --short --branch
sed -n '1,220p' AGENTS.md
sed -n '1,220p' docs/README.md
sed -n '1,220p' docs/design/runtime-contracts.md
```

Then check `docs/exec-plans/` for active work. If the change is multi-step,
risky, or likely to outlive the current session, create or update a plan from
`docs/exec-plans/TEMPLATE.md` before editing.

## Choose Validation

Use the smallest command set that covers the change.

Harness or documentation topology:

```bash
./tools/validate_harness.sh
```

Shell scripts:

```bash
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
```

Main entrypoint behavior:

```bash
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
```

Release packaging:

```bash
./tools/build_release_bundle.sh --version local-smoke --skip-zip
./tools/build_release_bundle.sh --version local-smoke
```

Release publication:

```bash
./tools/validate_harness.sh
./tools/test_dependency_parsing.sh
./tools/test_issue_10_regression.sh
./tools/test_issue_11_game_detection.sh
./tools/test_issue_12_agl_install_failure.sh
./tools/test_installer_rollback_regression.sh
./tools/test_support_bundle_sanitization.sh
./tools/test_backup_saves_regression.sh
./tools/test_launcher_friction.sh
./tools/test_preflight_regression.sh
./tools/test_manifest_regression.sh
./tools/test_qt_version_pinning.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --dry-run
./tools/build_release_bundle.sh --version vX.Y.Z --skip-zip
```

When cutting a release, bump `VERSION`, `CHANGELOG.md`, release examples, and
the bootstrap default tag together. If bootstrap exact-commit verification is
used, the release commit cannot contain its own hash. Cut and push the tag
first, verify the release workflow, then add a follow-up `main` commit pinning
the bootstrap commit guard to the tag target.

After the tag workflow publishes assets, verify:

```bash
gh run watch RUN_ID --exit-status
gh release view vX.Y.Z --json tagName,isDraft,isPrerelease,publishedAt,url,assets
gh release download vX.Y.Z -p "WormsWMD-macOS-Fix-vX.Y.Z.zip" -p "WormsWMD-macOS-Fix-vX.Y.Z.zip.sha256" -D /tmp/wormswmd-release-check
(cd /tmp/wormswmd-release-check && shasum -a 256 -c "WormsWMD-macOS-Fix-vX.Y.Z.zip.sha256")
gh attestation verify /tmp/wormswmd-release-check/WormsWMD-macOS-Fix-vX.Y.Z.zip --repo cboyd0319/WormsWMD-macOS-Fix
```

AGL stub or C source:

```bash
clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
rm -f /tmp/AGL_test
```

Runtime validation on macOS with the game installed:

```bash
./tools/preflight_check.sh --quick
./fix_worms_wmd.sh --verify
./tools/collect_diagnostics.sh --output ~/Desktop/worms-diagnostics.txt
```

## Collect Evidence

Use local artifacts when debugging or reporting failures:

- `~/Library/Logs/WormsWMD-Fix/` for fix and verification logs.
- `~/Library/Logs/WormsWMD/` for launcher logs and crash reports.
- `./tools/collect_diagnostics.sh` for a shareable diagnostics report.
- Exact terminal output for failed validation.

Redact account details, machine-private paths when needed, and any sensitive
config values before posting externally.

## Handoff Incomplete Work

If work is incomplete or blocked:

- Update the relevant file in `docs/exec-plans/`.
- Record the current status under `Progress`.
- Record unexpected findings under `Surprises & Discoveries`.
- Record choices already made under `Decision Log`.
- Name the exact next command or file edit needed.

Do not rely on chat history as the only handoff artifact.

## Clean-State Checklist

Before claiming work is complete:

```bash
git status --short
```

Confirm:

- Only intentional files changed.
- Relevant docs and execution plans match the implementation.
- Required validation commands ran, or the reason they could not run is clear.
- New local artifacts such as `/tmp/AGL_test` were removed.
- No logs, diagnostics, secrets, or generated support bundles were accidentally
  added to the repo.
