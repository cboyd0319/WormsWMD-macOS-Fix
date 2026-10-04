#!/bin/bash
#
# Worms W.M.D - macOS Fix Installer
#
# INSTRUCTIONS:
#   1. Download this file
#   2. Double-click to run
#   3. If macOS says the file can't be opened, right-click it and choose "Open"
#   4. Click "Open" in the dialog that appears
#
# Everything else is automatic!
#

set -euo pipefail

# Move to a sensible directory (in case we're in Downloads or somewhere weird)
cd "$HOME" || exit 1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                                                                ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     ${GREEN}${BOLD}Worms W.M.D - macOS Fix Installer${NC}                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                                ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     Supports macOS 26+ and macOS 27 Golden Gate.              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     The process is fully automatic.                           ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                                ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if git is available
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}Installing required tools...${NC}"
    echo ""
    echo "A dialog will appear asking to install developer tools."
    echo "Click 'Install' to continue."
    echo ""
    xcode-select --install 2>/dev/null || true
    echo ""
    echo "Please wait for the installation to complete, then run this installer again."
    echo ""
    read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
    exit 0
fi

REPO_URL="https://github.com/cboyd0319/WormsWMD-macOS-Fix"
INSTALL_DIR="$HOME/.wormswmd-fix"
INSTALL_REF="v1.7.9"
INSTALL_COMMIT="f5228270f1e813a79ced1d9aa1981c473845dad8"

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
    verify_install_commit "$checkout"
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

verify_install_commit() {
    local actual_commit
    local dir="${1:-$INSTALL_DIR}"

    actual_commit=$(bootstrap_git -C "$dir" rev-parse HEAD 2>/dev/null || true)
    if [[ -z "$INSTALL_COMMIT" || "$INSTALL_COMMIT" == PENDING_* ]]; then
        echo -e "${RED}Release commit pin is not finalized for $INSTALL_REF.${NC}"
        echo "Replace INSTALL_COMMIT with the final release commit before publishing."
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
    if [[ "$actual_commit" != "$INSTALL_COMMIT" ]]; then
        echo -e "${RED}Pinned release verification failed.${NC}"
        echo "Expected $INSTALL_COMMIT"
        echo "Got ${actual_commit:-unknown}"
        read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
        exit 1
    fi
}

# Download and verify a fresh checkout before replacing any old one.
prepare_installation

echo ""

# Sanity check
if [[ ! -f "$INSTALL_DIR/fix_worms_wmd.sh" ]]; then
    echo -e "${RED}Download incomplete: fix_worms_wmd.sh not found.${NC}"
    read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
    exit 1
fi

cd "$INSTALL_DIR" || exit 1

# Make scripts executable and run the friendly launcher when available.
chmod +x fix_worms_wmd.sh
if [[ -f "Worms W.M.D Fix.command" ]]; then
    chmod +x "Worms W.M.D Fix.command"
fi
if [[ -d scripts ]]; then
    shopt -s nullglob
    script_files=(scripts/*.sh)
    if (( ${#script_files[@]} )); then
        chmod +x "${script_files[@]}"
    fi
    shopt -u nullglob
fi
if [[ -d tools ]]; then
    shopt -s nullglob
    tool_files=(tools/*.sh)
    if (( ${#tool_files[@]} )); then
        chmod +x "${tool_files[@]}"
    fi
    shopt -u nullglob
fi

if [[ -f "Worms W.M.D Fix.command" ]]; then
    ./"Worms W.M.D Fix.command"
else
    ./fix_worms_wmd.sh
fi

# Keep the window open so user can see the result
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo "You can close this window now."
echo ""
read -n 1 -s -r -p "Press any key to exit..." < /dev/tty
