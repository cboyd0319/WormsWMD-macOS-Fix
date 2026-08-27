## Summary

Describe the focused change and why it is needed.

## Trust and user impact

- What files, downloads, permissions, backups, release assets, or user data are
  affected?
- What remains unchanged?

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
- [ ] I ran `./tools/test_github_security.sh` when `.github/`, release, or
      dependency automation changed.
