#!/bin/bash
#
# install.sh - One-liner installer for Worms W.M.D macOS Fix
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.7.4/install.sh | bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/v1.7.4/install.sh | bash -s -- --dry-run
#

set -euo pipefail

REPO_URL="https://github.com/cboyd0319/WormsWMD-macOS-Fix"
DEFAULT_INSTALL_REF="v1.7.4"
DEFAULT_INSTALL_COMMIT=""
INSTALL_DIR="${INSTALL_DIR:-$HOME/.wormswmd-fix}"
INSTALL_REF="${INSTALL_REF:-$DEFAULT_INSTALL_REF}"

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

install_dir_is_system_path() {
    local path="$1"

    case "$path" in
        /|/Applications|/Applications/*|/Library|/Library/*|/System|/System/*|/bin|/bin/*|/etc|/etc/*|/sbin|/sbin/*|/usr|/usr/*)
            return 0
            ;;
    esac

    return 1
}

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

    if [[ "$INSTALL_REF" != "$DEFAULT_INSTALL_REF" ]]; then
        case "${WORMSWMD_ALLOW_UNPINNED_REF:-}" in
            1|true|TRUE|yes|YES)
                print_info "Using developer-selected ref: $INSTALL_REF"
                ;;
            *)
                print_error "Default install is pinned to $DEFAULT_INSTALL_REF."
                print_info "Set WORMSWMD_ALLOW_UNPINNED_REF=1 only if you intentionally want another ref."
                exit 1
                ;;
        esac
    fi
}

normalize_install_dir() {
    local raw_dir="$INSTALL_DIR"
    local parent
    local base
    local home_real

    if [[ -z "$raw_dir" ]]; then
        print_error "INSTALL_DIR cannot be empty."
        exit 1
    fi

    if install_dir_is_system_path "$raw_dir"; then
        print_error "INSTALL_DIR must be a user-writable project directory, not a system path: $raw_dir"
        exit 1
    fi

    parent=$(dirname "$raw_dir")
    base=$(basename "$raw_dir")
    mkdir -p "$parent"
    parent=$(cd "$parent" && pwd -P)
    INSTALL_DIR="$parent/$base"
    home_real=$(cd "$HOME" && pwd -P)

    if install_dir_is_system_path "$INSTALL_DIR"; then
        print_error "INSTALL_DIR resolves to a system path: $INSTALL_DIR"
        exit 1
    fi

    if [[ "$INSTALL_DIR" == "/" ]] || [[ "$INSTALL_DIR" == "$home_real" ]]; then
        print_error "INSTALL_DIR cannot be the filesystem root or your home directory."
        exit 1
    fi
}

directory_is_empty() {
    local dir="$1"

    [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

repo_remote_matches() {
    local dir="$1"
    local remote

    remote=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)
    case "$remote" in
        "$REPO_URL"|"$REPO_URL.git"|git@github.com:cboyd0319/WormsWMD-macOS-Fix.git)
            return 0
            ;;
    esac

    return 1
}

clone_install_ref() {
    git clone --progress --branch "$INSTALL_REF" --depth 1 "$REPO_URL.git" "$INSTALL_DIR"
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

verify_default_install_commit() {
    local dir="$1"
    local actual_commit

    if [[ "$INSTALL_REF" != "$DEFAULT_INSTALL_REF" ]]; then
        return 0
    fi
    if [[ -z "$DEFAULT_INSTALL_COMMIT" ]]; then
        return 0
    fi
    if [[ "$DEFAULT_INSTALL_COMMIT" == PENDING_* ]]; then
        print_error "Release commit pin is not finalized for $DEFAULT_INSTALL_REF."
        print_info "Replace DEFAULT_INSTALL_COMMIT with the final release commit before publishing."
        exit 1
    fi

    actual_commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
    if [[ "$actual_commit" != "$DEFAULT_INSTALL_COMMIT" ]]; then
        print_error "Pinned release verification failed for $DEFAULT_INSTALL_REF."
        print_info "Expected $DEFAULT_INSTALL_COMMIT but got ${actual_commit:-unknown}."
        exit 1
    fi
}

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}     ${GREEN}Worms W.M.D - macOS 26+ Fix Installer${NC}                   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
print_step "Checking prerequisites..."
validate_install_ref
normalize_install_dir

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
    if ! repo_remote_matches "$INSTALL_DIR"; then
        print_error "INSTALL_DIR is a Git repository for a different remote: $INSTALL_DIR"
        print_info "Choose another INSTALL_DIR or move that repository yourself."
        exit 1
    fi
    print_info "Updating existing installation..."
    if checkout_install_ref "$INSTALL_DIR"; then
        : # Success
    else
        print_error "Update failed. Existing installation was left untouched: $INSTALL_DIR"
        exit 1
    fi
    verify_default_install_commit "$INSTALL_DIR"
else
    # Fresh installation
    if [[ -d "$INSTALL_DIR" ]]; then
        if ! directory_is_empty "$INSTALL_DIR"; then
            print_error "INSTALL_DIR already exists and is not an empty fix checkout: $INSTALL_DIR"
            print_info "Choose another INSTALL_DIR or move that directory yourself."
            exit 1
        fi
    fi
    clone_install_ref
    verify_default_install_commit "$INSTALL_DIR"
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
