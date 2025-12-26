# Contribute

Use this guide to report issues or submit changes.

## Report an issue

Before you file an issue, do these steps:
1. Check existing issues.
2. Verify game files in Steam.
3. Run `./fix_worms_wmd.sh --verify`.

Include this information:
- macOS version (`sw_vers -productVersion`)
- Mac model and chip (Intel or Apple Silicon)
- Error output or logs
- Log file path from `~/Library/Logs/WormsWMD-Fix/`
- Steps to reproduce
- Whether you tried `--restore` and re-applied the fix

Issue template:

macOS version: 26.x
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
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh
./fix_worms_wmd.sh --help
./fix_worms_wmd.sh --dry-run
./tools/check_updates.sh --help
./tools/collect_diagnostics.sh --help
```

## Make changes

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
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh tools/*.sh
./fix_worms_wmd.sh --dry-run
./fix_worms_wmd.sh --verify
```

If you change packaging or update tools, run the related scripts.

## Send a pull request

Include:
- A summary of the change
- Test results
- Any user-facing impact or migration steps
