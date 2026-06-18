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

GAME_APP="${GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app}"
OUTPUT_FILE=""
FULL_MODE=false
COPY_TO_CLIPBOARD=false
SUPPORT_BUNDLE=false
BUNDLE_OUTPUT_DIR="${BUNDLE_OUTPUT_DIR:-$HOME/Desktop}"
BUNDLE_TEMP_DIR=""

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

    package_dir="$(dirname "$package")"
    checksum_name="$(basename "${package}.sha256")"
    (cd "$package_dir" && shasum -a 256 -c "$checksum_name" >/dev/null 2>&1)
}

sanitize_report() {
    local input="$1"
    local output="$2"

    awk -v home="$HOME" '
        {
            gsub(home, "~")
            gsub(/\/Users\/[^\/[:space:]]+/, "/Users/[redacted-user]")
            gsub(/\/Volumes\/[^"<>]*/, "[redacted-path]")
            gsub(/\/private\/var\/[^"<>]*/, "[redacted-path]")
            gsub(/\/var\/folders\/[^"<>]*/, "[redacted-path]")
            gsub(/\/tmp\/[^"<>]*/, "[redacted-path]")
            gsub(/[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}/, "[redacted-email]")
            gsub(/([Tt]oken|[Ss]ecret|[Pp]assword|[Aa][Pp][Ii][_-]?[Kk]ey)[[:space:]]*[:=][[:space:]]*[^[:space:]]+/, "\\1=[redacted-secret]")
            print
        }
    ' "$input" > "$output"
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
    if xattr -l "$GAME_APP" 2>/dev/null | grep -q "quarantine"; then
        warn "Quarantine flag present (may cause launch issues)"
    else
        ok "No quarantine flags"
    fi

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
    local info_file="$bundle_dir/qt-package.txt"
    local local_qt_package=""

    {
        echo "Qt package status"
        echo "================="
        echo ""

        if [[ -f "$REPO_DIR/scripts/download_qt_frameworks.sh" ]]; then
            echo "Availability: $("$REPO_DIR/scripts/download_qt_frameworks.sh" --check 2>/dev/null || echo unavailable)"
        else
            echo "Availability: unavailable (download script missing)"
        fi

        local_qt_package=$(worms_latest_qt_package_by_version "$REPO_DIR/dist" true || true)
        if [[ -n "$local_qt_package" ]]; then
            echo "Local package: $(basename "$local_qt_package")"
            if verify_qt_package_checksum "$local_qt_package"; then
                echo "Checksum: verified"
            else
                echo "Checksum: mismatch"
            fi
            echo ""
            echo "Metadata:"
            tar -xOf "$local_qt_package" METADATA.txt 2>/dev/null || echo "(metadata unavailable)"
        else
            echo "Local package: none"
        fi
    } > "$info_file"
}

copy_backup_manifests() {
    local bundle_dir="$1"
    local manifests_dir="$bundle_dir/backup-manifests"
    local copied=0
    local backup manifest target_name

    mkdir -p "$manifests_dir"
    if [[ -d "$HOME/Documents" ]]; then
        while IFS= read -r -d '' backup; do
            manifest="$backup/BACKUP_MANIFEST.tsv"
            if [[ -f "$manifest" ]]; then
                target_name="$(basename "$backup").tsv"
                cp "$manifest" "$manifests_dir/$target_name"
                copied=$((copied + 1))
            fi
        done < <(find "$HOME/Documents" -mindepth 1 -maxdepth 1 -type d -name "WormsWMD-Backup-*" -print0 2>/dev/null)
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
        echo "This bundle contains sanitized diagnostics, Qt package status, and backup manifests."
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
    copy_backup_manifests "$BUNDLE_TEMP_DIR"

    COPYFILE_DISABLE=1 tar -czf "$bundle_path" -C "$BUNDLE_TEMP_DIR" .
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
