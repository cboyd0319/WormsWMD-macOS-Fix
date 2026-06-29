# Contribute

Use this guide to report issues or submit changes.

## Report an issue

Before you file an issue, do these steps:
1. Check existing issues.
2. Verify game files in Steam.
3. Run `Worms W.M.D Fix.command` and choose option 3, or run both
   `./tools/preflight_check.sh --quick` and `./fix_worms_wmd.sh --verify`.
4. If you need help, choose option 5 in the launcher and attach the support
   bundle.

Include this information:
- macOS version (`sw_vers -productVersion`)
- Mac model and chip (Intel or Apple Silicon)
- Error output or logs
- Log file path from `~/Library/Logs/WormsWMD-Fix/`
- Support bundle from `Worms W.M.D Fix.command` option 5, when available. It
  includes macOS and Rosetta details, sanitized installer history, runtime
  invariant status, Qt package checks, and backup integrity status.
- Steps to reproduce
- Whether you tried `--restore` and re-applied the fix

Issue template:

macOS version: 27.0 or 26.x
Mac model: MacBook Pro M4
Architecture: arm64

What happened:
[Describe the issue]

Expected behavior:
[Describe the expected result]

Terminal output:
[Paste output here]

Log file:
~/Library/Logs/WormsWMD-Fix/your-log-file.log

Trace file (if using --debug):
~/Library/Logs/WormsWMD-Fix/your-log-file.log.trace

Steps to reproduce:
1. Step one
2. Step two

## Set up a development environment

### Prerequisites

- macOS (Intel or Apple Silicon with Rosetta 2)
- ShellCheck (`brew install shellcheck`)
- Xcode Command Line Tools (`xcode-select --install`)

Optional for Homebrew fallback testing:
- Intel Homebrew (`/usr/local/bin/brew`)
- Qt 5 (`arch -x86_64 /usr/local/bin/brew install qt@5`)

### Clone the repository

```bash
git clone https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix
```

### Verify your setup

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
./tools/check_updates.sh --help
./tools/collect_diagnostics.sh --help
./tools/build_release_bundle.sh --version local-smoke --skip-zip
```

## Make changes

### Agent workflow

If you are using an AI coding agent or making a multi-step change:

1. Start with `AGENTS.md`, `docs/README.md`, and `docs/design/runtime-contracts.md`.
2. For multi-file or risky work, create or update a plan under `docs/exec-plans/` using `docs/exec-plans/TEMPLATE.md`.
3. Keep the plan current when scope, files, validation, or decisions change.
4. Run `./tools/validate_harness.sh` after changing agent instructions, docs topology, or Markdown links.

### Branch naming

- `fix/` for bug fixes (for example, `fix/rosetta-detection`)
- `feature/` for new features (for example, `feature/homebrew-tap`)
- `docs/` for documentation (for example, `docs/troubleshooting`)

### Commit messages

Use conventional commits:

```
<type>: short description

Longer description if needed.

Fixes #123
```

Types: `fix`, `feat`, `docs`, `refactor`, `test`, `chore`

## Test changes

At minimum, run:

```bash
./tools/validate_harness.sh
shellcheck fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh
for script in fix_worms_wmd.sh install.sh "Install Fix.command" "Worms W.M.D Fix.command" scripts/*.sh tools/*.sh; do bash -n "$script"; done
./fix_worms_wmd.sh --dry-run
./tools/build_release_bundle.sh --version local-smoke --skip-zip
```

For runtime validation, run `./fix_worms_wmd.sh --verify` after applying the
fix to a test game bundle. On an unfixed local install, `--verify` is expected
to report missing fix artifacts and should be recorded as a runtime state check,
not a source failure.

If you change packaging or update tools, run the related scripts.

## Send a pull request

Include:
- A summary of the change
- Test results
- Any user-facing impact or migration steps

Trust-sensitive files are covered by `.github/CODEOWNERS`; expect maintainer
review and passing CI before changes are merged to `main`.
