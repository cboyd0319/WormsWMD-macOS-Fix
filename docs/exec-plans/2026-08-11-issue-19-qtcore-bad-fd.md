# Issue 19 QtCore Bad File Descriptor

Status: Completed

## Problem

Issue #19 reports that v1.7.4 fails on macOS 26.6 while
`install_name_tool` rewrites the copied QtCore framework binary. The tool
returns `Bad file descriptor`, and the installer then rolls back successfully.
The shipped Qt archive stores framework binaries without an owner write bit,
while the replacement script copies those modes unchanged before mutating the
binaries.

## Scope and non-goals

- Add regression coverage for copied, owner-read-only Qt framework binaries in
  `tools/test_installer_rollback_regression.sh`.
- Make each copied framework binary owner-writable immediately before its
  install name is rewritten in `scripts/02_replace_qt_frameworks.sh`.
- Record the behavior in the runtime contract and changelog.
- Do not replace the Qt archive, change its checksum, alter backup or rollback
  behavior, or broaden framework mutation beyond the existing replacement
  loop.

## Constraints and risks

- The game bundle and user saves must remain protected by the existing backup
  and rollback flow.
- Paths may contain spaces and remain quoted.
- The fix must work with the Bash version shipped by macOS and preserve the
  current Windows repository experience.
- Local reproduction runs on macOS 27, where the installed
  `install_name_tool` tolerates a mode `0444` input. The regression uses a
  deterministic tool stub to reproduce the macOS 26.6 failure condition.

## Milestones

- [x] Milestone 1: Add a fixture whose Qt framework binaries are mode `0444`
  and whose `install_name_tool` stub rejects non-writable input.
- [x] Milestone 2: Run the focused regression and record the expected failure.
- [x] Milestone 3: Add the smallest permission normalization before the
  existing install-name rewrite and update `CHANGELOG.md` plus the runtime
  contract.
- [x] Milestone 4: Run focused regression, syntax, ShellCheck, harness, Qt
  package, and diff checks.
- [x] Milestone 5: Run the user-requested adversarial review, resolve material
  findings, and repeat affected checks.

## Verification

```bash
./tools/test_installer_rollback_regression.sh
bash -n scripts/02_replace_qt_frameworks.sh tools/test_installer_rollback_regression.sh
shellcheck scripts/02_replace_qt_frameworks.sh tools/test_installer_rollback_regression.sh
./scripts/download_qt_frameworks.sh --check
./tools/validate_harness.sh
git diff --check
```

The focused regression must fail before the production change because the
copied QtCore binary is not writable, then pass after the change. The Qt package
check must continue to verify the existing archive without modifying it.

## Progress

- 2026-08-11: Triaged issue #19 and inspected its sanitized support bundle.
- 2026-08-11: Confirmed v1.7.4, macOS 26.6 build 25G72, a verified Qt 5.15.19
  package, successful backup verification, and successful rollback.
- 2026-08-11: Confirmed the shipped archive stores QtCore as mode `0444` and
  the replacement loop copies that mode before calling `install_name_tool`.
- 2026-08-11: Added the regression fixture and confirmed it failed at QtCore
  with the reported `Bad file descriptor` condition before the production
  change.
- 2026-08-11: Added owner-write permission normalization to the copied
  framework binary immediately before the existing install-name rewrite.
- 2026-08-11: Focused regression, Bash syntax, ShellCheck, Qt package check,
  harness validation, and `git diff --check` passed before adversarial review.
- 2026-08-11: The real shipped Qt archive completed the replacement script in
  an isolated game bundle. All seven framework binaries became mode `0644`,
  retained the expected install IDs, and left the source archive copy at mode
  `0444`.
- 2026-08-11: The adversarial pass found no material implementation defect.
  It narrowed the changelog claim because macOS 26.6 was not available for a
  live rerun, then the complete scripted regression set and full Bash syntax
  and ShellCheck passes succeeded.

## Surprises & Discoveries

- The same isolated mode `0444` mutation succeeds with the macOS 27 Command
  Line Tools available on the maintainer machine, so the live macOS 26.6 error
  is version-specific or environment-specific. The installer should not rely
  on that permissive tool behavior.

## Decision Log

- Keep the archive unchanged. Normalizing the copied working binary is enough
  and avoids a 46 MB package replacement plus checksum churn.
- Extend the existing installer rollback regression check instead of creating
  another CI entrypoint for one permission invariant.

## Outcomes & Retrospective

The installer now makes each copied Qt framework binary owner-writable before
calling `install_name_tool`. The fail-first fixture reproduced the reported
QtCore error before the change and passed after it. The shipped package,
rollback, mutation-safety, manifest, support-bundle, launcher, preflight,
dependency, and prior issue regressions all passed without replacing the Qt
archive.

The remaining validation gap is a live retry by the reporter or another
macOS 26.6 system. Local real-payload verification ran on macOS 27 with Bash
3.2 and the installed Command Line Tools.
