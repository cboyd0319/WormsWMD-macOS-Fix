## Summary

Describe the focused change and why it is needed.

## Trust and user impact

- What files, downloads, permissions, backups, release assets, or user data are
  affected?
- What remains unchanged?

## Security-sensitive surfaces

- Which workflows, executable modes, symlinks, binaries, `dist` files,
  provenance, hooks, agent instructions, release tools, tests/test deletions,
  suppressions, or network/process calls changed?
- Explain each signal from `tools/report_sensitive_changes.sh`; the report is
  advisory and does not replace review of the complete file/mode diff.

## Verification

List the exact commands and manual checks that passed. Name any relevant check
that could not be run and why.

## Checklist

- [ ] This pull request contains one focused change.
- [ ] I reviewed the diff for secrets, private configuration, game binaries,
      save data, support bundles, logs, and machine-specific paths.
- [ ] New or changed executable downloads remain HTTPS-only, immutable or
      checksum-verified, and documented.
- [ ] Backup, restore, storefront, macOS, and Windows behavior remains covered
      where affected.
- [ ] Tests/checks and user-facing documentation match the changed behavior.
- [ ] I ran `./tools/validate_harness.sh`.
- [ ] I ran `./tools/test_harness_security.sh` and
      `./tools/test_sensitive_change_report.sh` when harness or contributor
      trust surfaces changed.
- [ ] The repository pre-commit hook completed, or I ran
      `./tools/install_git_hooks.sh` before committing.
- [ ] I ran `./tools/test_github_security.sh` when `.github/`, release, or
      dependency automation changed.
