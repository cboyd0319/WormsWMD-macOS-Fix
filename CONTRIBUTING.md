# Contributing to WormsWMD-macOS-Fix

Thank you for your interest in contributing! This document provides guidelines and information for contributors.

## Table of Contents

- [Reporting Issues](#reporting-issues)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Code Style](#code-style)

## Reporting Issues

Before creating an issue, please:

1. **Check existing issues** to avoid duplicates
2. **Verify game files** in Steam before reporting
3. **Run `--verify`** to check your installation: `./fix_worms_wmd.sh --verify`

### When reporting bugs, include:

- macOS version (`sw_vers -productVersion`)
- Mac model and chip (Intel or Apple Silicon)
- Complete error message or terminal output
- Steps to reproduce the issue
- Whether you tried `--restore` and re-applying

### Issue template:

```markdown
**macOS Version:** 26.x
**Mac Model:** MacBook Pro M4
**Architecture:** arm64

**What happened:**
[Description of the issue]

**Expected behavior:**
[What should have happened]

**Terminal output:**
```
[Paste output here]
```

**Steps to reproduce:**
1. Step one
2. Step two
```

## Development Setup

### Prerequisites

- macOS (Intel or Apple Silicon with Rosetta 2)
- Intel Homebrew (`/usr/local/bin/brew`)
- Qt 5 (`arch -x86_64 /usr/local/bin/brew install qt@5`)
- ShellCheck (`brew install shellcheck`)

### Clone the repository

```bash
git clone https://github.com/cboyd0319/WormsWMD-macOS-Fix.git
cd WormsWMD-macOS-Fix
```

### Verify your setup

```bash
# Run shellcheck on all scripts
shellcheck fix_worms_wmd.sh install.sh scripts/*.sh

# Test the help command
./fix_worms_wmd.sh --help

# Test dry-run mode (doesn't modify the game)
./fix_worms_wmd.sh --dry-run
```

## Making Changes

### Branch naming

- `fix/` - Bug fixes (e.g., `fix/rosetta-detection`)
- `feature/` - New features (e.g., `feature/homebrew-tap`)
- `docs/` - Documentation changes (e.g., `docs/troubleshooting`)

### Commit messages

Follow conventional commits:

```
type: short description

Longer description if needed.

Fixes #123
```

Types: `fix`, `feat`, `docs`, `refactor`, `test`, `chore`

## Testing

### Before submitting a PR:

1. **Run ShellCheck:**
   ```bash
   shellcheck -e SC2034 -e SC1091 fix_worms_wmd.sh install.sh scripts/*.sh
   ```

2. **Verify bash syntax:**
   ```bash
   bash -n fix_worms_wmd.sh
   bash -n scripts/*.sh
   ```

3. **Test the AGL stub compiles:**
   ```bash
   clang -Wall -Wextra -Werror -arch x86_64 -dynamiclib -o /tmp/AGL_test -framework OpenGL src/agl_stub.c
   ```

4. **Test on a real installation (if possible):**
   ```bash
   # Create a test backup first!
   ./fix_worms_wmd.sh --dry-run  # Preview changes
   ./fix_worms_wmd.sh            # Apply fix
   ./fix_worms_wmd.sh --verify   # Verify
   ./fix_worms_wmd.sh --restore  # Restore if needed
   ```

### Testing on different systems

If you have access to multiple Macs, please test on:

- Apple Silicon (M1/M2/M3/M4)
- Intel Mac
- Different macOS versions (26.0, 26.1, 26.2, etc.)

## Pull Request Process

1. **Fork the repository** and create your branch
2. **Make your changes** following the code style
3. **Run all tests** (shellcheck, syntax, compilation)
4. **Update documentation** if needed (README, CHANGELOG)
5. **Submit a PR** with a clear description

### PR template:

```markdown
## Summary
Brief description of changes.

## Type of change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring

## Testing done
- [ ] ShellCheck passes
- [ ] Bash syntax valid
- [ ] Tested on macOS [version]
- [ ] Tested on [Intel/Apple Silicon]

## Checklist
- [ ] Code follows project style
- [ ] Self-review completed
- [ ] Documentation updated (if needed)
- [ ] CHANGELOG updated (if user-facing change)
```

## Code Style

### Shell scripts

- Use `#!/bin/bash` shebang
- Use `set -e` for error handling
- Quote all variables: `"$variable"`
- Use `[[ ]]` instead of `[ ]`
- Use `$(command)` instead of backticks
- Add comments for complex logic
- Keep functions focused and small

### Formatting

```bash
# Good
if [[ -f "$file" ]]; then
    echo "File exists"
fi

# Bad
if [ -f $file ]; then
echo "File exists"
fi
```

### Error handling

```bash
# Good - informative errors
if [[ ! -d "$GAME_APP" ]]; then
    print_error "Game not found at: $GAME_APP"
    echo ""
    echo "Try setting GAME_APP to your game location:"
    echo "  GAME_APP=\"/path/to/game\" ./fix_worms_wmd.sh"
    exit 1
fi

# Bad - silent failure
[[ -d "$GAME_APP" ]] || exit 1
```

### Naming

- Functions: `snake_case` (e.g., `check_already_applied`)
- Variables: `UPPER_CASE` for constants, `lower_case` for locals
- Files: `kebab-case` for documentation, `snake_case.sh` for scripts

## Questions?

Open a [Discussion](https://github.com/cboyd0319/WormsWMD-macOS-Fix/discussions) or reach out in an issue.

Thank you for contributing! 🎮
