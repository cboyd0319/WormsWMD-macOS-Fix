#!/bin/bash
#
# collect_diagnostics.sh - System Diagnostics for Worms W.M.D Bug Reports
#
# Collects system information, game state, and fix status to help
# troubleshoot issues. Output can be attached to GitHub issues.
#
# Usage:
#   ./collect_diagnostics.sh [OPTIONS]
#
# Options:
#   --output FILE   Write to a .txt or .log file (default: stdout)
#   --full          Include extended diagnostics (larger output)
#   --copy          Copy output to clipboard (macOS)
#   --bundle        Create a sanitized support bundle for GitHub issues
#   --help          Show this help
#

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"

DEFAULT_GAME_PATH="$(worms_default_game_app)"
GAME_APP_EXPLICIT=false
if [[ -n "${GAME_APP:-}" ]]; then
    GAME_APP_EXPLICIT=true
fi
GAME_APP="${GAME_APP:-$DEFAULT_GAME_PATH}"
GAME_APP_AMBIGUOUS=false
DETECTED_GAME_APPS=()
OUTPUT_FILE=""
FULL_MODE=false
COPY_TO_CLIPBOARD=false
SUPPORT_BUNDLE=false
BUNDLE_OUTPUT_DIR="${BUNDLE_OUTPUT_DIR:-$HOME/Desktop}"
BUNDLE_TEMP_DIR=""
REQUIRED_QT_FRAMEWORKS=(
    QtCore
    QtGui
    QtWidgets
    QtOpenGL
    QtPrintSupport
    QtDBus
    QtSvg
)
REQUIRED_QT_PLUGINS=(
    platforms/libqcocoa.dylib
    imageformats/libqsvg.dylib
)
REQUIRED_BUNDLED_DYLIBS=(
    libglib-2.0.0.dylib
    libgthread-2.0.0.dylib
    libintl.8.dylib
    libpcre2-16.0.dylib
    libpcre2-8.0.dylib
    libzstd.1.dylib
    libpng16.16.dylib
    libjpeg.8.dylib
    libfreetype.6.dylib
    libmd4c.0.dylib
    liblzma.5.dylib
    libtiff.6.dylib
)

cleanup() {
    if [[ -n "$BUNDLE_TEMP_DIR" ]] && [[ -d "$BUNDLE_TEMP_DIR" ]]; then
        rm -rf "$BUNDLE_TEMP_DIR"
    fi
}
trap cleanup EXIT

verify_qt_package_checksum() {
    local package="$1"
    local package_dir
    local checksum_name

    [[ -f "${package}.sha256" ]] || return 1
    local package_size
    package_size=$(worms_file_size "$package" 2>/dev/null || echo 0)
    [[ "$package_size" =~ ^[0-9]+$ ]] \
        && (( package_size > 0 && package_size <= 64 * 1024 * 1024 )) \
        || return 1

    package_dir="$(dirname "$package")"
    checksum_name="$(basename "${package}.sha256")"
    (cd "$package_dir" && shasum -a 256 -c "$checksum_name" >/dev/null 2>&1)
}

fix_tool_version() {
    awk -F= '/^VERSION=/{gsub(/"/, "", $2); print $2; exit}' "$REPO_DIR/fix_worms_wmd.sh" 2>/dev/null
}

sanitize_report() {
    local input="$1"
    local output="$2"

    awk -v home="$HOME" '
        BEGIN {
            esc = sprintf("%c", 27)
            bel = sprintf("%c", 7)
            ansi = esc "\\[[0-9;]*[[:alpha:]]"
            osc_bel = esc "\\][^" bel "]*" bel
            osc_st = esc "\\][^" esc "]*" esc "\\\\"
            for (i = 1; i < 32; i++) {
                if (i != 9) controls[++control_count] = sprintf("%c", i)
            }
            controls[++control_count] = sprintf("%c", 127)
        }
        {
            gsub(osc_bel, "")
            gsub(osc_st, "")
            gsub(ansi, "")
            for (i = 1; i <= control_count; i++) gsub(controls[i], "")
            gsub(home, "~")
            gsub(/\/Users\/[^\/[:space:]]+/, "/Users/[redacted-user]")
            gsub(/\/Volumes\/[^"<>]*/, "[redacted-path]")
            gsub(/\/private\/var\/[^"<>]*/, "[redacted-path]")
            gsub(/\/var\/folders\/[^"<>]*/, "[redacted-path]")
            gsub(/\/tmp\/[^"<>]*/, "[redacted-path]")
            gsub(/[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}/, "[redacted-email]")
            gsub(/[Tt][Oo][Kk][Ee][Nn][[:space:]]*[:=][[:space:]]*[^[:space:]]+/, "token=[redacted-secret]")
            gsub(/[Ss][Ee][Cc][Rr][Ee][Tt][[:space:]]*[:=][[:space:]]*[^[:space:]]+/, "secret=[redacted-secret]")
            gsub(/[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*[:=][[:space:]]*[^[:space:]]+/, "password=[redacted-secret]")
            gsub(/[Aa][Pp][Ii][_-][Kk][Ee][Yy][[:space:]]*[:=][[:space:]]*[^[:space:]]+/, "api_key=[redacted-secret]")
            gsub(/[Aa][Pp][Ii][Kk][Ee][Yy][[:space:]]*[:=][[:space:]]*[^[:space:]]+/, "apikey=[redacted-secret]")
            print
        }
    ' "$input" > "$output"
}

latest_fix_logs() {
    local log_dir="$HOME/Library/Logs/WormsWMD-Fix"
    local log_file mtime

    [[ -d "$log_dir" ]] || return 0

    find "$log_dir" -maxdepth 1 -type f -name 'fix_worms_wmd-*.log' -print0 2>/dev/null \
        | while IFS= read -r -d '' log_file; do
            if worms_has_control_chars "$log_file"; then
                continue
            fi
            mtime=$(stat -f "%m" "$log_file" 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$mtime" "$log_file"
        done \
        | sort -nr \
        | awk -F '\t' 'NR <= 5 { sub(/^[^\t]*\t/, ""); print }'
}

infer_log_outcome() {
    local log_file="$1"
    local line outcome="unknown"

    while IFS= read -r line; do
        if [[ "$line" == *"Rolled back to original state."* ]] \
            || [[ "$line" == *"Rolled back to original game files."* ]]; then
            outcome="failure: rollback completed"
        elif [[ "$line" == *"ERROR:"* || "$line" == *"✗"* ]]; then
            outcome="failure or warning: inspect timeline"
        elif [[ "$line" == *"FIX COMPLETE!"* ]]; then
            outcome="success: fix complete"
        elif [[ "$line" == *"Dry run complete"* ]]; then
            outcome="success: dry run"
        elif [[ "$line" == *"SUCCESS: All checks passed"* ]]; then
            outcome="success: verification passed"
        fi
    done < "$log_file"

    echo "$outcome"
}

emit_sanitized_diagnostics() {
    local raw_report
    local sanitized_report

    raw_report=$(mktemp "${TMPDIR:-/tmp}/wormswmd-diagnostics-raw.XXXXXX")
    sanitized_report=$(mktemp "${TMPDIR:-/tmp}/wormswmd-diagnostics.XXXXXX")

    collect_diagnostics > "$raw_report"
    sanitize_report "$raw_report" "$sanitized_report"
    cat "$sanitized_report"
    rm -f "$raw_report" "$sanitized_report"
}

# Colors (disabled for file output)
setup_colors() {
    if [[ -t 1 ]] && [[ -z "$OUTPUT_FILE" ]] && ! $SUPPORT_BUNDLE; then
        worms_color_init always
    else
        worms_color_init never
    fi
}

print_help() {
    cat << 'EOF'
Worms W.M.D - System Diagnostics Collector

Collects system information for bug reports and troubleshooting.

USAGE:
    ./collect_diagnostics.sh [OPTIONS]

OPTIONS:
    --output FILE   Write diagnostics to a .txt or .log file
    --full          Include extended diagnostics (library details, etc.)
    --copy          Copy output to clipboard (macOS pbcopy)
    --bundle        Create a sanitized .tar.gz support bundle
    --bundle-output DIR
                   Write support bundle to DIR (default: ~/Desktop)
    --help, -h      Show this help message

EXAMPLES:
    # Print to terminal
    ./collect_diagnostics.sh

    # Save to file for GitHub issue
    ./collect_diagnostics.sh --output ~/Desktop/worms-diagnostics.txt

    # Copy to clipboard
    ./collect_diagnostics.sh --copy

    # Full diagnostics to file
    ./collect_diagnostics.sh --full --output ~/Desktop/worms-full-diagnostics.txt

    # Create a bundle to attach to a GitHub issue
    ./collect_diagnostics.sh --bundle

EOF
}

section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BOLD}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

subsection() {
    echo ""
    echo -e "${CYAN}▶ $1${NC}"
}

ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
}

info() {
    echo "  $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                echo "ERROR: --output requires a file path"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --full)
            FULL_MODE=true
            shift
            ;;
        --copy)
            COPY_TO_CLIPBOARD=true
            shift
            ;;
        --bundle|--support-bundle)
            SUPPORT_BUNDLE=true
            shift
            ;;
        --bundle-output)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                echo "ERROR: --bundle-output requires a directory"
                exit 1
            fi
            BUNDLE_OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if ! $GAME_APP_EXPLICIT; then
    while IFS= read -r -d '' detected_game; do
        DETECTED_GAME_APPS+=("$detected_game")
    done < <(worms_find_game_apps)

    if [[ ${#DETECTED_GAME_APPS[@]} -eq 1 ]]; then
        GAME_APP="${DETECTED_GAME_APPS[0]}"
    elif [[ ${#DETECTED_GAME_APPS[@]} -gt 1 ]]; then
        GAME_APP=""
        GAME_APP_AMBIGUOUS=true
    fi
fi

# Setup output
setup_colors

prepare_output_file() {
    local output_file="$1"

    worms_reject_control_chars "$output_file" "output file"
    case "$output_file" in
        *.txt|*.log)
            ;;
        *)
            echo "ERROR: --output must end with .txt or .log"
            exit 1
            ;;
    esac

    mkdir -p "$(dirname "$output_file")"
    if [[ -L "$output_file" ]] || [[ -d "$output_file" ]]; then
        echo "ERROR: --output must be a regular file path"
        exit 1
    fi
}

worms_reject_control_chars "$GAME_APP" "GAME_APP"
worms_reject_control_chars "$BUNDLE_OUTPUT_DIR" "bundle output directory"
if [[ -n "$OUTPUT_FILE" ]]; then
    prepare_output_file "$OUTPUT_FILE"
fi

collect_diagnostics() {
    section "WORMS W.M.D DIAGNOSTICS REPORT"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Report Version: 1.0"

    # ================================================================
    section "SYSTEM INFORMATION"
    # ================================================================

    subsection "macOS Version"
    local macos_version macos_build
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    macos_build=$(sw_vers -buildVersion 2>/dev/null || echo "unknown")
    info "Version: $macos_version ($macos_build)"
    info "Product: $(sw_vers -productName 2>/dev/null || echo "macOS")"

    subsection "Hardware"
    local cpu_brand chip_type
    cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    chip_type=$(uname -m)
    info "CPU: $cpu_brand"
    info "Architecture: $chip_type"
    info "Cores: $(sysctl -n hw.ncpu 2>/dev/null || echo "Unknown")"
    info "Memory: $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB"

    subsection "Graphics"
    # Get GPU info from system_profiler
    local gpu_info
    gpu_info=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|VRAM|Metal" | head -6 || echo "Unable to detect")
    echo "$gpu_info" | while read -r line; do
        [[ -n "$line" ]] && info "$line"
    done

    subsection "Rosetta 2"
    if [[ "$chip_type" == "arm64" ]]; then
        local rosetta_pkg_info rosetta_pkg_version
        rosetta_pkg_info=$(pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto 2>/dev/null || true)
        if [[ -n "$rosetta_pkg_info" ]]; then
            ok "Rosetta package receipt: present"
            rosetta_pkg_version=$(printf '%s\n' "$rosetta_pkg_info" | awk -F': *' '/^version:/ {print $2; exit}')
            info "Rosetta package version: ${rosetta_pkg_version:-unknown}"
        else
            warn "Rosetta package receipt: missing"
            info "Rosetta package version: unavailable"
        fi

        if /usr/bin/pgrep -q oahd 2>/dev/null; then
            ok "oahd process: running"
        else
            warn "oahd process: not running"
        fi

        if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
            ok "x86_64 execution probe: passed"
            ok "Rosetta 2 is installed and working"
        else
            fail "x86_64 execution probe: failed"
            fail "Rosetta 2 is NOT installed"
        fi

        if command -v game-test-tool >/dev/null 2>&1; then
            info "game-test-tool status:"
            game-test-tool status 2>&1 | while IFS= read -r line; do
                [[ -n "$line" ]] && info "  $line"
            done
        else
            info "game-test-tool status: unavailable"
        fi
    else
        info "Not applicable (Intel Mac)"
    fi

    # ================================================================
    section "GAME STATUS"
    # ================================================================

    subsection "Game Location"
    if $GAME_APP_AMBIGUOUS; then
        warn "Multiple installations detected; set GAME_APP to the installation being diagnosed."
        local detected_game
        for detected_game in "${DETECTED_GAME_APPS[@]}"; do
            info "Detected: $detected_game"
        done
    elif [[ -d "$GAME_APP" ]]; then
        ok "Found: $GAME_APP"

        local game_exec="$GAME_APP/Contents/MacOS/Worms W.M.D"
        if [[ -f "$game_exec" ]]; then
            ok "Executable exists"
            info "Architecture: $(lipo -archs "$game_exec" 2>/dev/null || echo "Unknown")"
            info "Size: $(du -h "$game_exec" 2>/dev/null | cut -f1 || echo "Unknown")"
        else
            fail "Executable missing!"
        fi
    else
        fail "Game not found at: $GAME_APP"
        if [[ "$GAME_APP" == "$DEFAULT_GAME_PATH" ]]; then
            warn "Searched common Steam, GOG, Applications, and Games folders"
        fi
        warn "Set GAME_APP environment variable if installed elsewhere"
    fi

    subsection "Fix Status"
    if [[ -d "$GAME_APP/Contents/Frameworks" ]]; then
        # Check AGL stub
        local agl_path="$GAME_APP/Contents/Frameworks/AGL.framework/Versions/A/AGL"
        if [[ -f "$agl_path" ]]; then
            local agl_archs agl_size
            agl_archs=$(lipo -archs "$agl_path" 2>/dev/null || echo "unknown")
            agl_size=$(stat -f%z "$agl_path" 2>/dev/null || echo "0")
            if ! echo "$agl_archs" | tr ' ' '\n' | grep -qx "x86_64"; then
                fail "AGL stub missing x86_64 architecture (archs: $agl_archs)"
            elif [[ "$agl_size" -lt 100000 ]]; then
                ok "AGL stub installed (archs: $agl_archs, size: ${agl_size} bytes)"
            else
                warn "AGL framework present but may not be stub (size: ${agl_size} bytes)"
            fi
        else
            fail "AGL stub NOT installed"
        fi

        # Check Qt version
        local qt_core="$GAME_APP/Contents/Frameworks/QtCore.framework/Versions/5/QtCore"
        if [[ -f "$qt_core" ]]; then
            local qt_info
            qt_info=$(otool -L "$qt_core" 2>/dev/null | head -2 | tail -1 || echo "unknown")
            if echo "$qt_info" | grep -q "5.15"; then
                ok "Qt 5.15 installed (fix applied)"
            elif echo "$qt_info" | grep -q "5.3"; then
                fail "Qt 5.3.2 (original, needs fix)"
            else
                info "Qt version: $qt_info"
            fi
        else
            warn "QtCore not found"
        fi

        # Check for bundled dependencies
        local dep_count
        dep_count=$(find "$GAME_APP/Contents/Frameworks" -name "lib*.dylib" -type f 2>/dev/null | wc -l | tr -d ' ')
        info "Bundled dylibs: $dep_count"

        # Check QtDBus
        if [[ -d "$GAME_APP/Contents/Frameworks/QtDBus.framework" ]]; then
            ok "QtDBus.framework present"
        else
            fail "QtDBus.framework missing"
        fi

        # Check QtSvg
        if [[ -d "$GAME_APP/Contents/Frameworks/QtSvg.framework" ]]; then
            ok "QtSvg.framework present"
        else
            fail "QtSvg.framework missing"
        fi

        if [[ -f "$GAME_APP/Contents/PlugIns/platforms/libqcocoa.dylib" ]]; then
            ok "Qt platform plugin present"
        else
            fail "Qt platform plugin missing"
        fi

        if [[ -f "$GAME_APP/Contents/PlugIns/imageformats/libqsvg.dylib" ]]; then
            ok "Qt SVG image plugin present"
        else
            fail "Qt SVG image plugin missing"
        fi
    else
        fail "Frameworks directory not found"
    fi

    subsection "Code Signing"
    local signature_classification quarantine_state
    signature_classification=$(worms_classify_bundle_signature "$GAME_APP")
    case "$signature_classification" in
        fixed-valid-adhoc) ok "Strict ad-hoc signature verified" ;;
        fixed-valid) ok "Strict code signature verified" ;;
        fixed-unsigned|fixed-invalid|fixed-unavailable)
            fail "Complete fixed app strict signature: ${signature_classification#fixed-}"
            ;;
        original-unsigned|original-invalid|original-unavailable)
            warn "Original/unfixed app signature: ${signature_classification#original-}"
            ;;
        *) info "Signature verifies; runtime fix is incomplete" ;;
    esac

    subsection "Quarantine Status"
    quarantine_state=$(worms_quarantine_state "$GAME_APP" 20)
    case "$quarantine_state" in
        none) ok "No recursive quarantine flags" ;;
        present:*) warn "Recursive quarantine: ${quarantine_state#present:} entries (names omitted)" ;;
        unavailable) warn "Quarantine inspection unavailable" ;;
        *) warn "Recursive quarantine inspection failed" ;;
    esac

    # ================================================================
    section "QT SOURCE STATUS"
    # ================================================================

    subsection "Pre-built Qt Package"
    local prebuilt_status local_qt_package
    prebuilt_status="unavailable"
    if [[ -f "$REPO_DIR/scripts/download_qt_frameworks.sh" ]]; then
        chmod +x "$REPO_DIR/scripts/download_qt_frameworks.sh" 2>/dev/null || true
        prebuilt_status=$("$REPO_DIR/scripts/download_qt_frameworks.sh" --check 2>/dev/null || echo "unavailable")
    fi

    if [[ "$prebuilt_status" == "available" ]]; then
        ok "Pre-built Qt frameworks available"
    else
        warn "Pre-built Qt frameworks not available"
        info "The installer can use Intel Homebrew Qt as a fallback."
    fi

    local_qt_package=$(worms_latest_qt_package_by_version "$REPO_DIR/dist" true || true)
    if [[ -n "$local_qt_package" ]]; then
        info "Local package: $(basename "$local_qt_package")"
        if [[ -f "${local_qt_package}.sha256" ]]; then
            if verify_qt_package_checksum "$local_qt_package"; then
                ok "Local package checksum verified"
            else
                fail "Local package checksum mismatch"
            fi
        else
            warn "Local package checksum file missing"
        fi
    else
        info "No local dist package found"
    fi

    subsection "Intel Homebrew"
    if [[ -f "/usr/local/bin/brew" ]]; then
        ok "Intel Homebrew found"
        local brew_version
        brew_version=$(/usr/local/bin/brew --version 2>/dev/null | head -1 || echo "unknown")
        info "Version: $brew_version"
    else
        warn "Intel Homebrew not found (only needed if pre-built Qt is unavailable)"
    fi

    subsection "Homebrew Qt 5 Installation"
    if [[ -d "/usr/local/opt/qt@5" ]]; then
        ok "Qt 5 found"
        local qt5_version
        local qt5_version_path
        qt5_version_path=$(worms_latest_path_by_mtime "/usr/local/Cellar/qt@5" "*" "d")
        if [[ -n "$qt5_version_path" ]]; then
            qt5_version=$(basename "$qt5_version_path")
        else
            qt5_version="unknown"
        fi
        info "Version: $qt5_version"

        if [[ -d "/usr/local/opt/qt@5/lib/QtCore.framework" ]]; then
            ok "QtCore.framework present"
        else
            fail "QtCore.framework missing"
        fi
    else
        warn "Homebrew Qt 5 not found (fallback unavailable)"
        info "Fallback install: arch -x86_64 /usr/local/bin/brew install qt@5"
    fi

    # ================================================================
    section "LIBRARY DEPENDENCIES"
    # ================================================================

    if [[ -d "$GAME_APP" ]]; then
        subsection "Executable Dependency Resolution"
        local game_exec="$GAME_APP/Contents/MacOS/Worms W.M.D"
        if [[ -f "$game_exec" ]]; then
            local dep resolved rpath dependency_issues=0

            while IFS= read -r rpath; do
                [[ -n "$rpath" ]] && info "LC_RPATH: $rpath"
            done < <(worms_macho_rpaths "$game_exec")

            while IFS= read -r dep; do
                case "$dep" in
                    @executable_path/*|@loader_path/*)
                        resolved=$(worms_expand_macho_path "$dep" "$game_exec" "$game_exec" || true)
                        if [[ -z "$resolved" ]] \
                            || ! worms_path_inside_root "$GAME_APP/Contents" "$resolved"; then
                            fail "$dep resolves outside the selected app"
                            dependency_issues=$((dependency_issues + 1))
                        elif [[ -f "$resolved" ]]; then
                            ok "$dep resolves to ${resolved#"$GAME_APP"/}"
                        elif worms_macho_dependency_is_weak "$game_exec" "$dep"; then
                            warn "$dep is optional and missing"
                            dependency_issues=$((dependency_issues + 1))
                        else
                            fail "$dep is required and missing"
                            dependency_issues=$((dependency_issues + 1))
                        fi
                        ;;
                    @rpath/*)
                        resolved=$(worms_resolve_macho_rpath_dependency "$game_exec" "$dep" "$game_exec" "$GAME_APP" || true)
                        if [[ -n "$resolved" ]]; then
                            ok "$dep resolves to ${resolved#"$GAME_APP"/}"
                        elif worms_macho_dependency_is_weak "$game_exec" "$dep"; then
                            warn "$dep is optional and unresolved"
                            dependency_issues=$((dependency_issues + 1))
                        else
                            fail "$dep is required and unresolved"
                            dependency_issues=$((dependency_issues + 1))
                        fi
                        ;;
                    /usr/local/*)
                        warn "External dependency: $dep"
                        dependency_issues=$((dependency_issues + 1))
                        ;;
                    /usr/lib/*|/System/Library/*)
                        ;;
                    *)
                        fail "Unportable relative dependency: $dep"
                        dependency_issues=$((dependency_issues + 1))
                        ;;
                esac
            done < <(worms_otool_dependencies "$game_exec")

            if [[ "$dependency_issues" -eq 0 ]]; then
                ok "No unresolved or external executable dependencies"
            fi
        fi

        subsection "FMOD Libraries"
        local fmod_ex="$GAME_APP/Contents/Frameworks/libfmodex.dylib"
        if [[ -f "$fmod_ex" ]]; then
            local fmod_archs fmod_deps
            fmod_archs=$(lipo -archs "$fmod_ex" 2>/dev/null || echo "unknown")
            info "libfmodex.dylib: $fmod_archs"

            fmod_deps=$(otool -L "$fmod_ex" 2>/dev/null | grep -E "libstdc|libgcc" || echo "")
            if [[ -n "$fmod_deps" ]]; then
                warn "FMOD uses deprecated runtime libraries:"
                echo "$fmod_deps" | while read -r line; do
                    info "  $line"
                done
            fi
        else
            info "libfmodex.dylib not found"
        fi

        subsection "Steam API"
        local steam_api="$GAME_APP/Contents/Frameworks/libsteam_api.dylib"
        if [[ -f "$steam_api" ]]; then
            local steam_archs steam_deps
            steam_archs=$(lipo -archs "$steam_api" 2>/dev/null || echo "unknown")
            info "libsteam_api.dylib: $steam_archs"

            steam_deps=$(otool -L "$steam_api" 2>/dev/null | grep -E "libstdc|libgcc" || echo "")
            if [[ -n "$steam_deps" ]]; then
                warn "Steam API uses deprecated runtime libraries:"
                echo "$steam_deps" | while read -r line; do
                    info "  $line"
                done
            fi
        else
            info "libsteam_api.dylib not found"
        fi
    fi

    # ================================================================
    # Extended diagnostics (--full mode)
    # ================================================================

    if $FULL_MODE; then
        section "EXTENDED DIAGNOSTICS"

        subsection "All Frameworks"
        if [[ -d "$GAME_APP/Contents/Frameworks" ]]; then
            while IFS= read -r -d '' entry; do
                local entry_rel entry_type entry_size
                entry_rel=${entry#"$GAME_APP/Contents/Frameworks/"}
                if [[ -d "$entry" ]]; then
                    entry_type="directory"
                    entry_size="-"
                else
                    entry_type="file"
                    entry_size=$(worms_file_size "$entry" 2>/dev/null || echo "?")
                fi
                info "$entry_type $entry_size Frameworks/$entry_rel"
            done < <(find "$GAME_APP/Contents/Frameworks" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
        fi

        subsection "All Bundled Libraries"
        if [[ -d "$GAME_APP/Contents/Frameworks" ]]; then
            find "$GAME_APP/Contents/Frameworks" -name "*.dylib" -type f 2>/dev/null | while read -r lib; do
                local lib_name lib_archs
                lib_name=$(basename "$lib")
                lib_archs=$(lipo -archs "$lib" 2>/dev/null || echo "?")
                info "$lib_name ($lib_archs)"
            done
        fi

        subsection "Plugins"
        if [[ -d "$GAME_APP/Contents/PlugIns" ]]; then
            find "$GAME_APP/Contents/PlugIns" -name "*.dylib" -type f 2>/dev/null | while read -r plugin; do
                local plugin_rel
                plugin_rel=${plugin#"$GAME_APP/Contents/PlugIns/"}
                info "$plugin_rel"
            done
        fi

        subsection "Info.plist Keys"
        if [[ -f "$GAME_APP/Contents/Info.plist" ]]; then
            for key in CFBundleIdentifier CFBundleVersion LSMinimumSystemVersion NSHighResolutionCapable DTXcode DTSDKName; do
                local value
                value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$GAME_APP/Contents/Info.plist" 2>/dev/null || echo "(not set)")
                info "$key: $value"
            done
        fi

        subsection "Recent Crash Logs"
        local crash_dir="$HOME/Library/Logs/DiagnosticReports"
        if [[ -d "$crash_dir" ]]; then
            local crashes
            crashes=$(find "$crash_dir" -name "*Worms*" -type f -mtime -7 2>/dev/null | head -5)
            if [[ -n "$crashes" ]]; then
                warn "Crash logs found from last 7 days:"
                echo "$crashes" | while read -r crash; do
                    info "  $(basename "$crash")"
                done
            else
                ok "No recent crash logs"
            fi
        fi

        subsection "Fix Tool Backups"
        local backup_count
        if [[ -d "$HOME/Documents" ]]; then
            backup_count=$(find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print 2>/dev/null | wc -l | tr -d ' ')
        else
            backup_count=0
        fi
        info "Backup directories found: $backup_count"
        if [[ "$backup_count" -gt 0 ]]; then
            find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print0 2>/dev/null \
                | while IFS= read -r -d '' backup; do
                    if worms_has_control_chars "$backup"; then
                        continue
                    fi
                    mtime=$(stat -f "%m" "$backup" 2>/dev/null || echo 0)
                    printf '%s\t%s\n' "$mtime" "$backup"
                done \
                | sort -nr \
                | head -3 \
                | cut -f2- \
                | while IFS= read -r backup; do
                    [[ -n "$backup" ]] || continue
                    info "  $(basename "$backup")"
                done
        fi
    fi

    # ================================================================
    section "SUMMARY"
    # ================================================================

    echo ""
    echo "To include this report in a GitHub issue:"
    echo "1. Copy the output above"
    echo "2. Paste into the issue as a code block:"
    echo '   ```'
    echo "   (paste diagnostics here)"
    echo '   ```'
    echo ""
    echo "Repository: https://github.com/cboyd0319/WormsWMD-macOS-Fix"
    echo "Issues: https://github.com/cboyd0319/WormsWMD-macOS-Fix/issues"
}

write_qt_package_bundle_info() {
    local bundle_dir="$1"
    local raw_file="$bundle_dir/qt-package.raw.txt"
    local info_file="$bundle_dir/qt-package.txt"
    local local_qt_package=""
    local listing_file required_fw required_plugin required_dylib entry
    local archive_temp_dir="" inspected_archive="" expected_sha256=""
    local checksum_verified=false inspection_ready=false
    local python_available=false

    worms_python3 >/dev/null && python_available=true

    {
        echo "Qt package status"
        echo "================="
        echo ""

        if ! $python_available; then
            echo "Availability: unavailable (compatible Python/CLT missing)"
        elif [[ -f "$REPO_DIR/scripts/download_qt_frameworks.sh" ]]; then
            echo "Availability: $("$REPO_DIR/scripts/download_qt_frameworks.sh" --check 2>/dev/null || echo unavailable)"
        else
            echo "Availability: unavailable (download script missing)"
        fi

        local_qt_package=$(worms_latest_qt_package_by_version "$REPO_DIR/dist" false || true)
        if [[ -n "$local_qt_package" ]]; then
            echo "Local package: $(basename "$local_qt_package")"
            if [[ -f "${local_qt_package}.sha256" ]]; then
                if verify_qt_package_checksum "$local_qt_package"; then
                    echo "Checksum: verified"
                    checksum_verified=true
                else
                    echo "Checksum: mismatch"
                fi
            else
                echo "Checksum: missing"
            fi
            if ! $python_available; then
                echo "Archive inspection: unavailable (compatible Python/CLT missing)"
            elif ! $checksum_verified; then
                echo "Archive inspection: skipped (verified checksum unavailable)"
            else
                expected_sha256=$(awk 'NR == 1 {print $1; exit}' "${local_qt_package}.sha256")
                archive_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-diagnostic-qt.XXXXXX")
                inspected_archive="$archive_temp_dir/package.tar.gz"
                if worms_copy_and_inspect_archive \
                    "$local_qt_package" "$inspected_archive" qt "$expected_sha256" --quiet \
                    >/dev/null 2>&1; then
                    echo "Archive inspection: passed"
                    inspection_ready=true
                else
                    echo "Archive inspection: failed"
                fi
            fi

            if $inspection_ready; then
                echo ""
                echo "Metadata:"
                tar -xOf "$inspected_archive" METADATA.txt 2>/dev/null || echo "(metadata unavailable)"
                echo ""
                echo "Required archive contents"
                echo "========================="

                listing_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-qt-listing.XXXXXX")
                if tar -tzf "$inspected_archive" > "$listing_file" 2>/dev/null; then
                for required_fw in "${REQUIRED_QT_FRAMEWORKS[@]}"; do
                    entry="Frameworks/${required_fw}.framework/Versions/5/${required_fw}"
                    if grep -Fxq "$entry" "$listing_file"; then
                        echo "PASS framework binary: $entry"
                    else
                        echo "FAIL framework binary missing: $entry"
                    fi
                done

                for required_plugin in "${REQUIRED_QT_PLUGINS[@]}"; do
                    entry="PlugIns/$required_plugin"
                    if grep -Fxq "$entry" "$listing_file"; then
                        echo "PASS plugin: $entry"
                    else
                        echo "FAIL plugin missing: $entry"
                    fi
                done

                for required_dylib in "${REQUIRED_BUNDLED_DYLIBS[@]}"; do
                    entry="Frameworks/$required_dylib"
                    if grep -Fxq "$entry" "$listing_file"; then
                        echo "PASS bundled dylib: $entry"
                    else
                        echo "FAIL bundled dylib missing: $entry"
                    fi
                done

                if grep -Fxq "MANIFEST.txt" "$listing_file"; then
                    echo "PASS manifest: MANIFEST.txt"
                else
                    echo "WARN manifest missing: MANIFEST.txt"
                fi
                if grep -Fxq "SOURCE_PROVENANCE.tsv" "$listing_file"; then
                    echo "PASS source provenance: SOURCE_PROVENANCE.tsv"
                else
                    echo "WARN source provenance missing: SOURCE_PROVENANCE.tsv"
                fi
                else
                    echo "FAIL unable to list inspected archive contents"
                fi
            fi
            rm -f "${listing_file:-}"
        else
            echo "Local package: none"
        fi
    } > "$raw_file"

    if [[ -n "$archive_temp_dir" ]] && [[ -d "$archive_temp_dir" ]]; then
        rm -rf "$archive_temp_dir"
    fi

    sanitize_report "$raw_file" "$info_file"
    rm -f "$raw_file"
}

write_install_summary() {
    local bundle_dir="$1"
    local raw_file="$bundle_dir/install-summary.raw.txt"
    local summary_file="$bundle_dir/install-summary.txt"
    local version git_commit git_ref release_line log_file log_name log_mtime log_size outcome logs_list_file

    {
        echo "Install history summary"
        echo "======================="
        echo ""

        version=$(fix_tool_version || true)
        echo "Fix tool version: ${version:-unknown}"
        if [[ -d "$REPO_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
            git_commit=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)
            git_ref=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
            echo "Git ref: ${git_ref:-unknown}"
            echo "Git commit: ${git_commit:-unknown}"
        elif [[ -f "$REPO_DIR/RELEASE_INFO.txt" ]]; then
            release_line=$(awk -F': ' '/^Version:/{print $2; exit}' "$REPO_DIR/RELEASE_INFO.txt")
            echo "Release bundle version: ${release_line:-unknown}"
        else
            echo "Source ref: unavailable"
        fi
        echo ""
        echo "Latest installer logs"
        echo "====================="

        logs_list_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-fix-logs.XXXXXX")
        latest_fix_logs > "$logs_list_file"

        if [[ ! -s "$logs_list_file" ]]; then
            echo "No fix_worms_wmd logs found in ~/Library/Logs/WormsWMD-Fix."
        else
            while IFS= read -r log_file; do
                [[ -n "$log_file" ]] || continue
                log_name=$(basename "$log_file")
                log_mtime=$(date -r "$log_file" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "unknown")
                log_size=$(worms_file_size "$log_file" 2>/dev/null || echo "unknown")
                outcome=$(infer_log_outcome "$log_file")

                echo ""
                echo "Log: $log_name"
                echo "Modified: $log_mtime"
                echo "Size bytes: $log_size"
                echo "Inferred outcome: $outcome"
                echo "Step timeline:"
                grep -E '^(==>|.*(Log file:|Game found:|ERROR:|SUCCESS:|Rolled back|Rolling back|Backup created|Backup manifest|All checks passed|Installation verification failed|Copying dependencies failed|AGL stub built successfully|Qt frameworks installed|Bundled dependencies verified|Dependencies copied|Dependencies prepared|FIX COMPLETE|Dry run complete|Pre-flight checks|Creating backup|Building AGL|Replacing Qt|Copying dependencies|Fixing library paths|Applying enhancements|Applying finishing touches|Verifying installation))' "$log_file" \
                    | tail -80 || true
            done < "$logs_list_file"
        fi
        rm -f "$logs_list_file"
    } > "$raw_file"

    sanitize_report "$raw_file" "$summary_file"
    rm -f "$raw_file"
}

write_runtime_invariants() {
    local bundle_dir="$1"
    local raw_file="$bundle_dir/runtime-invariants.raw.txt"
    local summary_file="$bundle_dir/runtime-invariants.txt"
    local frameworks_dir="$GAME_APP/Contents/Frameworks"
    local plugins_dir="$GAME_APP/Contents/PlugIns"
    local agl_path="$frameworks_dir/AGL.framework/Versions/A/AGL"
    local required_fw required_plugin required_dylib binary dylib archs size rel_path qt_info

    {
        echo "Required runtime invariant matrix"
        echo "================================="
        echo ""
        echo "Game app: $GAME_APP"
        echo ""

        if [[ ! -d "$GAME_APP" ]]; then
            echo "FAIL game app not found"
        else
            echo "Storefront libraries"
            echo "--------------------"
            for dylib in "$GAME_APP/Contents/MacOS/"*.dylib; do
                [[ -f "$dylib" ]] || continue
                archs=$(lipo -archs "$dylib" 2>/dev/null || echo "unknown")
                if echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
                    echo "PASS MacOS dylib: $(basename "$dylib") ($archs)"
                else
                    echo "FAIL MacOS dylib missing x86_64: $(basename "$dylib") ($archs)"
                fi
            done

            echo ""
            echo "AGL"
            echo "---"
            if [[ -f "$agl_path" ]]; then
                archs=$(lipo -archs "$agl_path" 2>/dev/null || echo "unknown")
                size=$(worms_file_size "$agl_path" 2>/dev/null || echo "unknown")
                if echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
                    echo "PASS AGL binary: Frameworks/AGL.framework/Versions/A/AGL"
                else
                    echo "FAIL AGL binary missing x86_64: $archs"
                fi
                echo "AGL archs: $archs"
                echo "AGL size bytes: $size"
            else
                echo "FAIL AGL binary missing: Frameworks/AGL.framework/Versions/A/AGL"
            fi

            echo ""
            echo "Qt frameworks"
            echo "-------------"
            for required_fw in "${REQUIRED_QT_FRAMEWORKS[@]}"; do
                binary=$(worms_framework_binary "$frameworks_dir/${required_fw}.framework" "$required_fw" 2>/dev/null || true)
                if [[ -n "$binary" && -f "$binary" ]]; then
                    rel_path=${binary#"$GAME_APP/Contents/"}
                    archs=$(lipo -archs "$binary" 2>/dev/null || echo "unknown")
                    if echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
                        echo "PASS $required_fw: $rel_path ($archs)"
                    else
                        echo "FAIL $required_fw missing x86_64: $rel_path ($archs)"
                    fi
                else
                    echo "FAIL $required_fw binary missing"
                fi
            done
            if [[ -f "$frameworks_dir/QtCore.framework/Versions/5/QtCore" ]]; then
                qt_info=$(otool -L "$frameworks_dir/QtCore.framework/Versions/5/QtCore" 2>/dev/null | sed -n '2p' || true)
                echo "QtCore install name: ${qt_info:-unknown}"
            fi

            echo ""
            echo "Qt plugins"
            echo "----------"
            for required_plugin in "${REQUIRED_QT_PLUGINS[@]}"; do
                if [[ -f "$plugins_dir/$required_plugin" ]]; then
                    archs=$(lipo -archs "$plugins_dir/$required_plugin" 2>/dev/null || echo "unknown")
                    if echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
                        echo "PASS plugin: PlugIns/$required_plugin ($archs)"
                    else
                        echo "FAIL plugin missing x86_64: PlugIns/$required_plugin ($archs)"
                    fi
                else
                    echo "FAIL plugin missing: PlugIns/$required_plugin"
                fi
            done

            echo ""
            echo "Bundled dependency dylibs"
            echo "------------------------"
            for required_dylib in "${REQUIRED_BUNDLED_DYLIBS[@]}"; do
                if [[ -f "$frameworks_dir/$required_dylib" ]]; then
                    archs=$(lipo -archs "$frameworks_dir/$required_dylib" 2>/dev/null || echo "unknown")
                    if echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
                        echo "PASS dylib: Frameworks/$required_dylib ($archs)"
                    else
                        echo "FAIL dylib missing x86_64: Frameworks/$required_dylib ($archs)"
                    fi
                else
                    echo "FAIL dylib missing: Frameworks/$required_dylib"
                fi
            done
        fi
    } > "$raw_file"

    sanitize_report "$raw_file" "$summary_file"
    rm -f "$raw_file"
}

write_backup_summary() {
    local bundle_dir="$1"
    local raw_file="$bundle_dir/backup-summary.raw.txt"
    local summary_file="$bundle_dir/backup-summary.txt"
    local backup_count=0 backup manifest metadata mtime symlink_status manifest_status
    local game_source game_app_path executable_hash

    {
        echo "Backup integrity summary"
        echo "========================"
        echo ""

        if [[ ! -d "$HOME/Documents" ]]; then
            echo "Documents directory not found."
        else
            backup_count=$(find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print 2>/dev/null | wc -l | tr -d ' ')
            echo "Backup count: $backup_count"

            find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print0 2>/dev/null \
                | while IFS= read -r -d '' backup; do
                    mtime=$(stat -f "%m" "$backup" 2>/dev/null || echo 0)
                    printf '%s\t%s\n' "$mtime" "$backup"
                done \
                | sort -nr \
                | awk -F '\t' 'NR <= 5 { sub(/^[^\t]*\t/, ""); print }' \
                | while IFS= read -r backup; do
                    [[ -n "$backup" ]] || continue
                    manifest="$backup/BACKUP_MANIFEST.tsv"
                    mtime=$(date -r "$backup" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "unknown")
                    if worms_validate_tree_symlinks "$backup" >/dev/null 2>&1; then
                        symlink_status="PASS"
                    else
                        symlink_status="FAIL"
                    fi
                    if [[ -f "$manifest" ]]; then
                        if worms_verify_manifest "$backup" "$manifest" >/dev/null 2>&1; then
                            manifest_status="PASS"
                        else
                            manifest_status="FAIL"
                        fi
                    else
                        manifest_status="WARN missing"
                    fi

                    echo ""
                    echo "Backup: $(basename "$backup")"
                    echo "Modified: $mtime"
                    metadata="$backup/BACKUP_METADATA.tsv"
                    if [[ -f "$metadata" ]]; then
                        game_source=$(awk -F '\t' '$1 == "game_source" {print $2; exit}' "$metadata")
                        game_app_path=$(awk -F '\t' '$1 == "game_app_path" {sub(/^[^\t]*\t/, ""); print; exit}' "$metadata")
                        executable_hash=$(awk -F '\t' '$1 == "game_executable_sha256" {print $2; exit}' "$metadata")
                        echo "Game source: ${game_source:-unknown}"
                        echo "Game app: ${game_app_path:-unknown}"
                        echo "Executable SHA-256: ${executable_hash:-unknown}"
                    else
                        echo "Game source: unknown (legacy backup)"
                        echo "Game app: unknown (legacy backup)"
                    fi
                    echo "Symlink validation: $symlink_status"
                        echo "Manifest validation: $manifest_status"
                        if [[ -f "$manifest" ]]; then
                            echo "Manifest SHA-256: $(worms_file_sha256 "$manifest")"
                        fi
                    if [[ -d "$backup/Frameworks/AGL.framework" ]]; then
                        echo "Looks already fixed: yes (AGL.framework present)"
                    else
                        echo "Looks already fixed: unknown/no AGL.framework"
                    fi
                done
        fi
    } > "$raw_file"

    sanitize_report "$raw_file" "$summary_file"
    rm -f "$raw_file"
}

copy_backup_manifests() {
    local bundle_dir="$1"
    local manifests_dir="$bundle_dir/backup-manifests"
    local copied=0
    local backup manifest target_name manifest_hash
    local backups_file seen_hashes_file

    mkdir -p "$manifests_dir"
    if [[ -d "$HOME/Documents" ]]; then
        backups_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-support-backups.XXXXXX")
        seen_hashes_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-support-hashes.XXXXXX")
        find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print0 2>/dev/null \
            | while IFS= read -r -d '' backup; do
                if worms_has_control_chars "$backup"; then
                    continue
                fi
                printf '%s\t%s\n' "$(stat -f '%m' "$backup" 2>/dev/null || echo 0)" "$backup"
            done \
            | sort -nr \
            | awk -F '\t' 'NR <= 5 { sub(/^[^\t]*\t/, ""); print }' \
            > "$backups_file"

        while IFS= read -r backup; do
            manifest="$backup/BACKUP_MANIFEST.tsv"
            if [[ -f "$manifest" ]]; then
                manifest_hash=$(worms_file_sha256 "$manifest")
                if grep -Fqx "$manifest_hash" "$seen_hashes_file"; then
                    continue
                fi
                printf '%s\n' "$manifest_hash" >> "$seen_hashes_file"
                target_name="$(basename "$backup")-manifest.tsv"
                sanitize_report "$manifest" "$manifests_dir/$target_name"
                copied=$((copied + 1))
            fi
        done < "$backups_file"
        rm -f "$backups_file" "$seen_hashes_file"
    fi

    if [[ "$copied" -eq 0 ]]; then
        echo "No fix backup manifests were found." > "$manifests_dir/README.txt"
    fi
}

collect_support_bundle() {
    local output_dir="$BUNDLE_OUTPUT_DIR"
    local timestamp bundle_path raw_report was_full

    mkdir -p "$output_dir" 2>/dev/null || output_dir="$PWD"
    timestamp=$(date '+%Y%m%d-%H%M%S')
    bundle_path=$(worms_unique_path "$output_dir/wormswmd-support-$timestamp" ".tar.gz")
    BUNDLE_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-support.XXXXXX")

    {
        echo "Worms W.M.D macOS Fix support bundle"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Repository: https://github.com/cboyd0319/WormsWMD-macOS-Fix"
        echo ""
        echo "This bundle contains sanitized diagnostics, install history, runtime invariant status, Qt package status, and backup manifests."
        echo "It does not include save files, game binaries, or raw crash logs."
    } > "$BUNDLE_TEMP_DIR/README.txt"

    raw_report="$BUNDLE_TEMP_DIR/diagnostics.raw.txt"
    was_full=$FULL_MODE
    FULL_MODE=true
    collect_diagnostics > "$raw_report"
    FULL_MODE=$was_full
    sanitize_report "$raw_report" "$BUNDLE_TEMP_DIR/diagnostics.txt"
    rm -f "$raw_report"

    write_qt_package_bundle_info "$BUNDLE_TEMP_DIR"
    write_install_summary "$BUNDLE_TEMP_DIR"
    write_runtime_invariants "$BUNDLE_TEMP_DIR"
    write_backup_summary "$BUNDLE_TEMP_DIR"
    copy_backup_manifests "$BUNDLE_TEMP_DIR"

    COPYFILE_DISABLE=1 tar \
        --format ustar \
        --uid 0 \
        --gid 0 \
        --uname root \
        --gname wheel \
        -czf "$bundle_path" \
        -C "$BUNDLE_TEMP_DIR" .
    echo "Support bundle created: $bundle_path"
}

# Run diagnostics
if $SUPPORT_BUNDLE; then
    collect_support_bundle
elif [[ -n "$OUTPUT_FILE" ]]; then
    emit_sanitized_diagnostics > "$OUTPUT_FILE"
    echo "Diagnostics saved to: $OUTPUT_FILE"
elif $COPY_TO_CLIPBOARD; then
    if command -v pbcopy >/dev/null 2>&1; then
        emit_sanitized_diagnostics | pbcopy
        echo "Diagnostics copied to clipboard!"
    else
        echo "pbcopy not available; printing diagnostics to stdout."
        emit_sanitized_diagnostics
    fi
else
    emit_sanitized_diagnostics
fi
