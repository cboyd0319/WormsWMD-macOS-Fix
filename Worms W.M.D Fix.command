#!/bin/bash
#
# Friendly double-click launcher for the Worms W.M.D macOS fix.
#

set -euo pipefail

LAUNCHER_PATH="${BASH_SOURCE[0]}"
while [[ -L "$LAUNCHER_PATH" ]]; do
    LAUNCHER_DIR="$(cd -P "$(dirname "$LAUNCHER_PATH")" && pwd)"
    LAUNCHER_PATH="$(readlink "$LAUNCHER_PATH")"
    [[ "$LAUNCHER_PATH" != /* ]] && LAUNCHER_PATH="$LAUNCHER_DIR/$LAUNCHER_PATH"
done
LAUNCHER_DIR="$(cd -P "$(dirname "$LAUNCHER_PATH")" && pwd)"
TTY_DEVICE=""

if [[ -t 0 ]] && [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
    TTY_DEVICE="/dev/tty"
fi

# shellcheck disable=SC1091
source "$LAUNCHER_DIR/scripts/ui.sh"
# shellcheck disable=SC1091
source "$LAUNCHER_DIR/scripts/common.sh"
worms_color_init auto

print_line() {
    printf '%s\n' "$*"
}

read_answer() {
    local prompt="$1"
    local answer=""

    if [[ -n "$TTY_DEVICE" ]]; then
        printf '%s' "$prompt" > "$TTY_DEVICE"
        IFS= read -r answer < "$TTY_DEVICE" || answer=""
    else
        printf '%s' "$prompt" >&2
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

select_game_app_if_needed() {
    local game choice i
    local games=()

    if [[ -n "${GAME_APP:-}" ]]; then
        worms_reject_control_chars "$GAME_APP" "GAME_APP" || return 1
        export GAME_APP
        return 0
    fi

    while IFS= read -r -d '' game; do
        games+=("$game")
    done < <(worms_find_game_apps)

    if [[ ${#games[@]} -eq 0 ]]; then
        return 0
    fi
    if [[ ${#games[@]} -eq 1 ]]; then
        GAME_APP="${games[0]}"
        export GAME_APP
        return 0
    fi

    print_line ""
    worms_print_step "Choose the Worms W.M.D installation to use"
    i=1
    for game in "${games[@]}"; do
        printf '  %s) %s\n' "$i" "$game"
        i=$((i + 1))
    done

    while true; do
        choice=$(read_answer "Choose an installation [1-${#games[@]}]: ")
        if [[ "$choice" =~ ^[0-9]+$ ]] \
            && [[ "$choice" -ge 1 ]] \
            && [[ "$choice" -le ${#games[@]} ]]; then
            GAME_APP="${games[$((choice - 1))]}"
            export GAME_APP
            return 0
        fi
        if [[ -z "$choice" ]]; then
            worms_print_error "No installation was selected."
            return 1
        fi
        worms_print_warning "Choose a number between 1 and ${#games[@]}."
    done
}

create_support_bundle() {
    local output_dir="$HOME/Desktop"

    print_line ""
    worms_print_step "Creating a support bundle on your Desktop"
    select_game_app_if_needed || return 1
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

launch_game() {
    local default_game_path detected_game
    local game_app

    print_line ""
    worms_print_step "Launching Worms W.M.D"
    select_game_app_if_needed || return 1
    game_app="${GAME_APP:-}"

    if ! command -v open >/dev/null 2>&1; then
        worms_print_warning "Automatic launch is unavailable here."
        print_line "Open Worms W.M.D from Steam or GOG."
        return 1
    fi

    default_game_path="$(worms_default_game_app)"
    if [[ -z "$game_app" ]]; then
        game_app="$default_game_path"
        if [[ ! -d "$game_app" ]]; then
            detected_game=$(worms_first_detected_game_app || true)
            if [[ -n "$detected_game" ]]; then
                game_app="$detected_game"
            fi
        fi
    fi

    if [[ "$game_app" == *"/Steam/"* ]] && open "steam://run/327030" >/dev/null 2>&1; then
        worms_print_success "Steam was asked to launch Worms W.M.D."
        return 0
    fi

    if [[ -d "$game_app" ]] && open "$game_app" >/dev/null 2>&1; then
        worms_print_success "Worms W.M.D was opened."
        return 0
    fi

    if [[ -n "${GAME_APP:-}" ]]; then
        worms_print_warning "Could not launch the selected game installation automatically."
        printf 'Open this installation directly: %s\n' "$GAME_APP"
        return 1
    fi

    if open "steam://run/327030" >/dev/null 2>&1; then
        worms_print_success "Steam was asked to launch Worms W.M.D."
        return 0
    fi

    worms_print_warning "Could not launch the game automatically."
    print_line "Open Worms W.M.D from Steam or GOG."
    return 1
}

offer_launch_game() {
    local answer

    print_line ""
    answer=$(read_answer "Launch Worms W.M.D now? [Y/n] ")
    case "$answer" in
        n|N|no|No|NO)
            return 0
            ;;
        *)
            launch_game || true
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

    select_game_app_if_needed || return 1

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

run_launch_readiness_check() {
    local status=0

    print_banner
    worms_print_step "Checking launch readiness"
    print_line ""
    select_game_app_if_needed || return 1

    if "$LAUNCHER_DIR/tools/preflight_check.sh" --quick; then
        print_line ""
        worms_print_success "System readiness check passed."
    else
        status=$?
        print_line ""
        worms_print_error "System readiness check failed."
    fi

    print_line ""
    if "$LAUNCHER_DIR/fix_worms_wmd.sh" --verify; then
        print_line ""
        worms_print_success "Game bundle verification passed."
    else
        status=$?
        print_line ""
        worms_print_error "Game bundle verification failed."
    fi

    if [[ "$status" -ne 0 ]]; then
        print_line ""
        print_line "The game is not ready to launch yet. A support bundle is the easiest next step."
        offer_support_bundle
    fi

    return "$status"
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
    print_line "  ${BOLD}3${NC}) Check whether the game is ready to launch"
    print_line "  ${BOLD}4${NC}) Restore original game files from backup"
    print_line "  ${BOLD}5${NC}) Create a support bundle on the Desktop"
    print_line "  ${BOLD}6${NC}) Open the simple help file"
    print_line "  ${BOLD}7${NC}) Launch Worms W.M.D"
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
                if run_fix_engine "Applying the recommended fix"; then
                    if run_launch_readiness_check; then
                        offer_launch_game
                    fi
                fi
                pause_for_user
                ;;
            2)
                run_fix_engine "Previewing changes" --dry-run || true
                pause_for_user
                ;;
            3)
                run_launch_readiness_check || true
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
            7)
                launch_game || true
                pause_for_user
                ;;
            q|Q|quit|Quit|QUIT)
                print_line ""
                print_line "Okay. No changes were made from this menu choice."
                exit 0
                ;;
            *)
                print_line ""
                worms_print_warning "Please choose 1, 2, 3, 4, 5, 6, 7, or q."
                pause_for_user
                ;;
        esac
    done
}

main "$@"
