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
#   --output FILE   Write to specific file (default: stdout)
#   --full          Include extended diagnostics (larger output)
#   --copy          Copy output to clipboard (macOS)
#   --help          Show this help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/ui.sh"

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
OUTPUT_FILE=""
FULL_MODE=false
COPY_TO_CLIPBOARD=false

# Colors (disabled for file output)
setup_colors() {
    if [[ -t 1 ]] && [[ -z "$OUTPUT_FILE" ]]; then
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
    --output FILE   Write diagnostics to a file
    --full          Include extended diagnostics (library details, etc.)
    --copy          Copy output to clipboard (macOS pbcopy)
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

# Setup output
setup_colors

collect_diagnostics() {
    section "WORMS W.M.D DIAGNOSTICS REPORT"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Report Version: 1.0"

    # ================================================================
    section "SYSTEM INFORMATION"
    # ================================================================

    subsection "macOS Version"
    local macos_version macos_build
    macos_version=$(sw_vers -productVersion)
    macos_build=$(sw_vers -buildVersion)
    info "Version: $macos_version ($macos_build)"
    info "Product: $(sw_vers -productName)"

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
        if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
            ok "Rosetta 2 is installed and working"
        else
            fail "Rosetta 2 is NOT installed"
        fi
    else
        info "Not applicable (Intel Mac)"
    fi

    # ================================================================
    section "GAME STATUS"
    # ================================================================

    subsection "Game Location"
    if [[ -d "$GAME_APP" ]]; then
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
            if [[ "$agl_size" -lt 100000 ]]; then
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
            warn "QtDBus.framework missing"
        fi

        # Check QtSvg
        if [[ -d "$GAME_APP/Contents/Frameworks/QtSvg.framework" ]]; then
            ok "QtSvg.framework present"
        else
            warn "QtSvg.framework missing"
        fi
    else
        fail "Frameworks directory not found"
    fi

    subsection "Code Signing"
    local codesign_status
    codesign_status=$(codesign -dv "$GAME_APP" 2>&1 || echo "unsigned")
    if echo "$codesign_status" | grep -q "not signed"; then
        warn "App is not signed"
    elif echo "$codesign_status" | grep -q "adhoc"; then
        ok "Ad-hoc signed"
    elif echo "$codesign_status" | grep -q "Authority"; then
        ok "Signed"
    else
        info "Signing status: $codesign_status"
    fi

    subsection "Quarantine Status"
    local quarantine
    quarantine=$(xattr -l "$GAME_APP" 2>/dev/null | grep -c "quarantine" || echo "0")
    if [[ "$quarantine" == "0" ]]; then
        ok "No quarantine flags"
    else
        warn "Quarantine flag present (may cause launch issues)"
    fi

    # ================================================================
    section "HOMEBREW STATUS"
    # ================================================================

    subsection "Intel Homebrew"
    if [[ -f "/usr/local/bin/brew" ]]; then
        ok "Intel Homebrew found"
        local brew_version
        brew_version=$(/usr/local/bin/brew --version 2>/dev/null | head -1 || echo "unknown")
        info "Version: $brew_version"
    else
        fail "Intel Homebrew NOT found"
    fi

    subsection "Qt 5 Installation"
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
        fail "Qt 5 NOT found"
        info "Install with: arch -x86_64 /usr/local/bin/brew install qt@5"
    fi

    # ================================================================
    section "LIBRARY DEPENDENCIES"
    # ================================================================

    if [[ -d "$GAME_APP" ]]; then
        subsection "Unresolved Dependencies"
        local game_exec="$GAME_APP/Contents/MacOS/Worms W.M.D"
        if [[ -f "$game_exec" ]]; then
            local unresolved
            unresolved=$(otool -L "$game_exec" 2>/dev/null | grep -E "@rpath|/usr/local" | grep -v "^$game_exec" || echo "")
            if [[ -z "$unresolved" ]]; then
                ok "No unresolved @rpath or /usr/local references in executable"
            else
                warn "Unresolved references found:"
                echo "$unresolved" | while read -r line; do
                    info "  $line"
                done
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
                info "$(ls -la -d "$entry" 2>/dev/null || true)"
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

# Run diagnostics
if [[ -n "$OUTPUT_FILE" ]]; then
    collect_diagnostics > "$OUTPUT_FILE"
    echo "Diagnostics saved to: $OUTPUT_FILE"
elif $COPY_TO_CLIPBOARD; then
    if command -v pbcopy >/dev/null 2>&1; then
        collect_diagnostics | pbcopy
        echo "Diagnostics copied to clipboard!"
    else
        echo "pbcopy not available; printing diagnostics to stdout."
        collect_diagnostics
    fi
else
    collect_diagnostics
fi
