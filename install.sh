#!/bin/bash
#
# install.sh - One-liner installer for Worms W.M.D macOS Fix
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.6.3/install.sh | INSTALL_REF=v1.6.3 bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.6.3/install.sh | INSTALL_REF=v1.6.3 bash -s -- --dry-run
#

set -euo pipefail

REPO_URL="https://github.com/cboyd0319/WormsWMD-macOS-Fix"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.wormswmd-fix}"
INSTALL_REF="${INSTALL_REF:-main}"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' BLUE='' BOLD='' NC=''
fi

print_step() { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
print_error() { echo -e "${RED}✗${NC}  ${RED}ERROR:${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC}  ${GREEN}SUCCESS:${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC}  $1"; }

validate_install_ref() {
    if [[ -z "$INSTALL_REF" ]]; then
        print_error "INSTALL_REF cannot be empty."
        exit 1
    fi

    if [[ "$INSTALL_REF" == -* ]] || [[ "$INSTALL_REF" == *".."* ]] || [[ "$INSTALL_REF" == *"@{"* ]]; then
        print_error "Unsafe INSTALL_REF value: $INSTALL_REF"
        exit 1
    fi

    if [[ ! "$INSTALL_REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        print_error "INSTALL_REF may only contain letters, numbers, dots, underscores, slashes, and hyphens."
        exit 1
    fi
}

backup_install_dir() {
    local src="$1"
    local backup
    backup="${src}.backup.$(date +%s)"

    if mv "$src" "$backup"; then
        print_info "Existing install backed up to: $backup"
    else
        print_error "Failed to back up existing install at: $src"
        exit 1
    fi
}

clone_install_ref() {
    if [[ "$INSTALL_REF" == "main" ]]; then
        git clone --progress "$REPO_URL.git" "$INSTALL_DIR"
    else
        git clone --progress --branch "$INSTALL_REF" --depth 1 "$REPO_URL.git" "$INSTALL_DIR"
    fi
}

checkout_install_ref() {
    local dir="$1"

    if [[ "$INSTALL_REF" == "main" ]]; then
        if ! git -C "$dir" checkout main >/dev/null 2>&1; then
            git -C "$dir" checkout -B main origin/main
        fi
        git -C "$dir" pull --progress --ff-only origin main
        return
    fi

    print_info "Using trusted release/reference: $INSTALL_REF"
    if git -C "$dir" fetch --progress --force origin "refs/tags/$INSTALL_REF:refs/tags/$INSTALL_REF"; then
        git -C "$dir" checkout --detach "$INSTALL_REF"
        return
    fi

    git -C "$dir" fetch --progress --force origin "$INSTALL_REF"
    git -C "$dir" checkout --detach FETCH_HEAD
}

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}     ${GREEN}Worms W.M.D - macOS Tahoe Fix Installer${NC}                 ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
print_step "Checking prerequisites..."
validate_install_ref

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This fix is only for macOS."
    exit 1
fi

# Check for prerequisites
if ! command -v git &>/dev/null; then
    print_error "git is required but not installed."
    exit 1
fi

if ! command -v curl &>/dev/null; then
    print_error "curl is required but not installed."
    exit 1
fi

print_success "Prerequisites OK!"
echo ""

# Download/update the fix
print_step "Downloading fix..."

if [[ -f "$INSTALL_DIR" ]]; then
    print_error "INSTALL_DIR points to a file: $INSTALL_DIR"
    exit 1
fi

mkdir -p "$(dirname "$INSTALL_DIR")"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    print_info "Updating existing installation..."
    if checkout_install_ref "$INSTALL_DIR"; then
        : # Success
    else
        print_info "Update failed; reinstalling..."
        backup_install_dir "$INSTALL_DIR"
        clone_install_ref
    fi
else
    # Fresh installation
    if [[ -d "$INSTALL_DIR" ]]; then
        backup_install_dir "$INSTALL_DIR"
    fi
    clone_install_ref
fi

print_success "Fix downloaded to: $INSTALL_DIR"
echo ""

# Sanity check
if [[ ! -f "$INSTALL_DIR/fix_worms_wmd.sh" ]]; then
    print_error "Download incomplete: fix_worms_wmd.sh not found."
    exit 1
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/fix_worms_wmd.sh"
if [[ -f "$INSTALL_DIR/Worms W.M.D Fix.command" ]]; then
    chmod +x "$INSTALL_DIR/Worms W.M.D Fix.command"
fi
if [[ -d "$INSTALL_DIR/scripts" ]]; then
    shopt -s nullglob
    script_files=("$INSTALL_DIR/scripts/"*.sh)
    if (( ${#script_files[@]} )); then
        chmod +x "${script_files[@]}"
    fi
    shopt -u nullglob
fi
if [[ -d "$INSTALL_DIR/tools" ]]; then
    shopt -s nullglob
    tool_files=("$INSTALL_DIR/tools/"*.sh)
    if (( ${#tool_files[@]} )); then
        chmod +x "${tool_files[@]}"
    fi
    shopt -u nullglob
fi

# Run the fix
print_step "Running fix..."
echo ""

cd "$INSTALL_DIR"
if [[ $# -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]] && [[ -f "Worms W.M.D Fix.command" ]]; then
    ./"Worms W.M.D Fix.command"
else
    ./fix_worms_wmd.sh "$@"
fi
