# Issue 20 GOG Galaxy rpath

Status: Completed

## Problem

The GOG executable depends on `@rpath/libGalaxy.dylib`, stored under
`Contents/MacOS`. The path rewrite only inventories `Contents/Frameworks`, so
verification rejects an otherwise local dependency and rolls back the fix.

## Scope and non-goals

Rewrite safe `@rpath` dependencies found beside the executable and add a
regression check. Do not special-case Galaxy, change Qt packaging, or alter
game detection.

## Constraints and risks

Reject parent-path escapes, preserve paths containing spaces, and keep backup,
rollback, signing, and verification behavior unchanged.

## Milestones

- [x] Confirm issue #20 against the GOG installation and trace the rewrite.
- [x] Add the smallest generic rewrite and regression check.
- [x] Run source and live-install verification.
- [x] Record results and complete the plan.

## Verification

- `./tools/test_dependency_parsing.sh`
- `./tools/test_installer_rollback_regression.sh`
- `./tools/test_mutation_safety.sh`
- `./tools/validate_harness.sh`
- `shellcheck scripts/04_fix_library_paths.sh tools/test_dependency_parsing.sh`
- Bash syntax checks, installer dry-run, live apply, and post-apply verify.

## Progress

- 2026-08-21: Reproduced the verifier failure and confirmed the GOG library is
  under `Contents/MacOS` with an executable-relative runtime search path.
- 2026-08-21: Added the guarded rewrite and a compiled Mach-O regression case.
- 2026-08-21: Source gates, live apply, verifier, and explicit-path preflight
  passed against `/Applications/Worms W.M.D.app`.

## Surprises & Discoveries

The original GOG bundle intentionally stores Galaxy beside the executable,
unlike the Qt dependencies stored under `Contents/Frameworks`.

The unqualified preflight selected an incomplete default Steam-path copy;
setting `GAME_APP` to the detected GOG bundle produced the relevant result.

## Decision Log

- Rewrite any safe, existing executable-adjacent `@rpath` dependency instead of
  hard-coding `libGalaxy.dylib` or weakening verification globally.

## Outcomes & Retrospective

The GOG dependency is rewritten without a name-specific exception. Dependency,
rollback, mutation-safety, preflight regression, harness, Bash syntax,
ShellCheck, release-build, dry-run, live-apply, verification, signature, and
explicit-path preflight checks passed. The live installer preserved a verified
backup before applying the fix.
