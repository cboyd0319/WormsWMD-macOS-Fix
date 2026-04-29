#!/bin/bash
#
# Friendly double-click launcher for the Worms W.M.D macOS fix.
#

set -euo pipefail

LAUNCHER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
TTY_DEVICE=""

if [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
    TTY_DEVICE="/dev/tty"
fi

# shellcheck disable=SC1091
source "$LAUNCHER_DIR/scripts/ui.sh"
worms_color_init auto

print_line() {
    printf '%b\n' "$*"
}

read_answer() {
    local prompt="$1"
    local answer=""

    if [[ -n "$TTY_DEVICE" ]]; then
        printf '%b' "$prompt" > "$TTY_DEVICE"
        IFS= read -r answer < "$TTY_DEVICE" || answer=""
    else
        printf '%b' "$prompt"
        IFS= read -r answer || answer=""
    fi

    printf '%s\n' "$answer"
}

pause_for_user() {
    read_answer "${DIM}Press Return to continue...${NC}" >/dev/null
}

open_file_or_print_path() {
    local path="$1"

    if command -v open >/dev/null 2>&1; then
        if open "$path"; then
            return 0
        fi
    fi

    print_line "Open this file for help:"
    print_line "  $path"
}

print_banner() {
    if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
        clear || true
    fi

    print_line ""
    print_line "${CYAN}+------------------------------------------------------------+${NC}"
    print_line "${CYAN}|${NC}  ${BOLD}${GREEN}Worms W.M.D macOS Fix${NC}                                  ${CYAN}|${NC}"
    print_line "${CYAN}|${NC}  ${YELLOW}Double-click helper for regular humans${NC}                    ${CYAN}|${NC}"
    print_line "${CYAN}+------------------------------------------------------------+${NC}"
    print_line ""
}

ensure_ready() {
    local missing=false

    if [[ "$(uname)" != "Darwin" ]]; then
        worms_print_error "This fix is only for macOS."
        exit 1
    fi

    if [[ ! -f "$LAUNCHER_DIR/fix_worms_wmd.sh" ]]; then
        worms_print_error "Missing fix_worms_wmd.sh next to this launcher."
        missing=true
    fi

    if [[ ! -f "$LAUNCHER_DIR/tools/collect_diagnostics.sh" ]]; then
        worms_print_error "Missing tools/collect_diagnostics.sh next to this launcher."
        missing=true
    fi

    if $missing; then
        print_line ""
        print_line "Download the complete release zip, unzip it, then run this file again."
        pause_for_user
        exit 1
    fi

    chmod +x "$LAUNCHER_DIR/fix_worms_wmd.sh" "$LAUNCHER_DIR/tools/collect_diagnostics.sh" 2>/dev/null || true
}

create_support_bundle() {
    local output_dir="$HOME/Desktop"

    print_line ""
    worms_print_step "Creating a support bundle on your Desktop"
    if BUNDLE_OUTPUT_DIR="$output_dir" "$LAUNCHER_DIR/tools/collect_diagnostics.sh" --bundle --bundle-output "$output_dir"; then
        worms_print_success "Support bundle created."
        if command -v open >/dev/null 2>&1; then
            open "$output_dir" >/dev/null 2>&1 || true
        fi
    else
        worms_print_error "Support bundle creation failed."
        print_line "You can still open an issue and paste the text shown above."
    fi
}

offer_support_bundle() {
    local answer

    print_line ""
    answer=$(read_answer "Create a support bundle for a GitHub issue? [Y/n] ")
    case "$answer" in
        n|N|no|No|NO)
            return 0
            ;;
        *)
            create_support_bundle
            ;;
    esac
}

run_fix_engine() {
    local title="$1"
    local status
    shift

    print_banner
    worms_print_step "$title"
    print_line ""

    if "$LAUNCHER_DIR/fix_worms_wmd.sh" "$@"; then
        print_line ""
        worms_print_success "Finished."
        return 0
    else
        status=$?
        print_line ""
        worms_print_error "That action did not finish successfully."
        print_line "Nothing here uses admin privileges. If something failed, a support bundle is the easiest next step."
        offer_support_bundle
        return "$status"
    fi
}

open_help() {
    local help_file="$LAUNCHER_DIR/README_FIRST.txt"

    if [[ ! -f "$help_file" ]]; then
        help_file="$LAUNCHER_DIR/README.md"
    fi

    open_file_or_print_path "$help_file"
}

print_menu() {
    print_banner
    print_line "Choose an option:"
    print_line ""
    print_line "  ${BOLD}1${NC}) Apply the recommended fix"
    print_line "  ${BOLD}2${NC}) Preview what will change"
    print_line "  ${BOLD}3${NC}) Check whether the fix is installed"
    print_line "  ${BOLD}4${NC}) Restore original game files from backup"
    print_line "  ${BOLD}5${NC}) Create a support bundle on the Desktop"
    print_line "  ${BOLD}6${NC}) Open the simple help file"
    print_line "  ${BOLD}q${NC}) Quit"
    print_line ""
}

main() {
    local choice

    cd "$LAUNCHER_DIR"
    ensure_ready

    while true; do
        print_menu
        choice=$(read_answer "Type a number and press Return: ")

        case "$choice" in
            1)
                run_fix_engine "Applying the recommended fix" || true
                pause_for_user
                ;;
            2)
                run_fix_engine "Previewing changes" --dry-run || true
                pause_for_user
                ;;
            3)
                run_fix_engine "Checking fix status" --verify || true
                pause_for_user
                ;;
            4)
                run_fix_engine "Restoring original game files" --restore || true
                pause_for_user
                ;;
            5)
                create_support_bundle
                pause_for_user
                ;;
            6)
                open_help
                pause_for_user
                ;;
            q|Q|quit|Quit|QUIT)
                print_line ""
                print_line "Okay. No changes were made from this menu choice."
                exit 0
                ;;
            *)
                print_line ""
                worms_print_warning "Please choose 1, 2, 3, 4, 5, 6, or q."
                pause_for_user
                ;;
        esac
    done
}

main "$@"
