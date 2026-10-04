#!/bin/bash
#
# install.sh - One-liner installer for Worms W.M.D macOS Fix
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/cboyd0319/WormsWMD-macOS-Fix/main/install.sh | bash -s -- --dry-run
#

set -euo pipefail

REPO_URL="https://github.com/cboyd0319/WormsWMD-macOS-Fix"
DEFAULT_INSTALL_REF="v1.7.9"
DEFAULT_INSTALL_COMMIT="f5228270f1e813a79ced1d9aa1981c473845dad8"
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
    if [[ "$base" == . || "$base" == .. ]]; then
        print_error "INSTALL_DIR must name a dedicated project directory."
        exit 1
    fi
    if ! parent=$(cd "$parent" && pwd -P); then
        print_error "INSTALL_DIR must have an existing parent directory."
        exit 1
    fi
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

# Ignore inherited Git configuration and disable executable hooks.
bootstrap_git() (
    local name
    for name in "${!GIT_@}"; do unset "$name"; done
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c init.templateDir= "$@"
)

# A private parent and trusted ancestors prevent another account replacing paths.
verify_install_parent() {
    local path="$1" owner mode metadata acl first=1
    [[ -O "$path" ]] || return 1
    while :; do
        metadata=$(/usr/bin/stat -f '%u %p' "$path") || return 1
        owner=${metadata%% *}
        mode=${metadata##* }
        [[ "$owner" == 0 || "$owner" == "$EUID" ]] || return 1
        [[ "$mode" =~ ^[0-7]{5,6}$ ]] || return 1
        if (( (8#$mode & 0022) != 0 )); then
            # A root/user-owned sticky ancestor protects its owned child.
            (( first == 0 && (8#$mode & 01000) != 0 )) || return 1
        fi
        acl=$(/bin/ls -lde "$path") || return 1
        if printf '%s\n' "$acl" | grep -Eq '^[[:space:]]*[0-9]+:.* allow '; then
            return 1
        fi
        [[ "$path" != / ]] || return 0
        path=$(dirname "$path")
        first=0
    done
}

prepare_installation() (
    local stage="" lock="$INSTALL_DIR.bootstrap-lock" remote checkout_status parent checkout
    parent=$(cd "$(dirname "$INSTALL_DIR")" && pwd -P) || return 1
    if ! verify_install_parent "$parent"; then
        printf 'Use an INSTALL_DIR parent owned by you, without shared write access or allow ACLs: %s\n' "$parent" >&2
        return 1
    fi
    umask 077
    if [[ -L "$INSTALL_DIR" || ( -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ) ]]; then
        printf 'Refusing a symlink or non-directory INSTALL_DIR: %s\n' "$INSTALL_DIR" >&2
        return 1
    fi
    if ! mkdir "$lock"; then
        printf 'Another bootstrap may be running; inspect lock: %s\n' "$lock" >&2
        return 1
    fi
    trap 'if [[ -n "$stage" && ! -e "$stage/previous" ]]; then rm -rf "$stage"; fi; rmdir "$lock"' EXIT
    if [[ -d "$INSTALL_DIR" ]] && ! directory_is_empty "$INSTALL_DIR"; then
        if [[ ! -d "$INSTALL_DIR/.git" || -L "$INSTALL_DIR/.git" ||
              ! -f "$INSTALL_DIR/.git/config" || -L "$INSTALL_DIR/.git/config" ]]; then
            printf 'Existing directory is not a fix checkout; move it yourself: %s\n' "$INSTALL_DIR" >&2
            return 1
        fi
        remote=$(bootstrap_git config --no-includes --file "$INSTALL_DIR/.git/config" --get remote.origin.url) || return 1
        case "$remote" in
            "$REPO_URL"|"$REPO_URL.git"|git@github.com:cboyd0319/WormsWMD-macOS-Fix.git) ;;
            *) printf 'Existing checkout has a different remote; move it yourself: %s\n' "$INSTALL_DIR" >&2; return 1 ;;
        esac
    fi
    stage=$(mktemp -d "$INSTALL_DIR.bootstrap.XXXXXX") || return 1
    mkdir "$stage/new" || return 1
    checkout="$stage/new/$(basename "$INSTALL_DIR")"
    bootstrap_git clone --progress --no-checkout --branch "$INSTALL_REF" --depth 1 \
        "$REPO_URL.git" "$checkout" || return 1
    verify_default_install_commit "$checkout"
    bootstrap_git -C "$checkout" checkout --detach HEAD || return 1
    checkout_status=$(bootstrap_git -C "$checkout" status --porcelain --untracked-files=all) || return 1
    if [[ -n "$checkout_status" ||
          ! -f "$checkout/fix_worms_wmd.sh" ]]; then
        printf 'Downloaded checkout is incomplete or modified; refusing execution.\n' >&2
        return 1
    fi
    if [[ -d "$INSTALL_DIR" ]]; then
        mv "$INSTALL_DIR" "$stage/previous" || return 1
    fi
    # Naming the parent makes mv rename to the exact basename, never nest inside
    # a concurrently created INSTALL_DIR. Staging is on the same filesystem.
    if ! mv "$checkout" "$parent/"; then
        if [[ -d "$stage/previous" && ! -e "$INSTALL_DIR" && ! -L "$INSTALL_DIR" ]]; then
            mv "$stage/previous" "$INSTALL_DIR" || return 1
        fi
        return 1
    fi
    if [[ -d "$stage/previous" ]]; then
        printf 'Previous checkout preserved at: %s/previous\n' "$stage"
    fi
)

verify_default_install_commit() {
    local dir="$1"
    local actual_commit

    if [[ "$INSTALL_REF" != "$DEFAULT_INSTALL_REF" ]]; then
        return 0
    fi
    if [[ -z "$DEFAULT_INSTALL_COMMIT" || "$DEFAULT_INSTALL_COMMIT" == PENDING_* ]]; then
        print_error "Release commit pin is not finalized for $DEFAULT_INSTALL_REF."
        print_info "Replace DEFAULT_INSTALL_COMMIT with the final release commit before publishing."
        exit 1
    fi

    actual_commit=$(bootstrap_git -C "$dir" rev-parse HEAD 2>/dev/null || true)
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

prepare_installation

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
