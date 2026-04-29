#!/bin/bash
#
# Build a user-facing release folder and optional zip archive.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/ui.sh"
worms_color_init auto

OUTPUT_DIR="$ROOT_DIR/build/release"
VERSION="${VERSION:-}"
SKIP_ZIP=false
COPIED_ITEMS=()

usage() {
    cat << 'EOF'
Build a Worms W.M.D macOS Fix release bundle.

USAGE:
    ./tools/build_release_bundle.sh [OPTIONS]

OPTIONS:
    --output-dir DIR   Write bundle output under DIR (default: build/release)
    --version VERSION  Use VERSION in the folder and zip name
    --skip-zip         Create the folder and manifest, but skip zip/checksum
    --help, -h         Show this help

OUTPUT:
    build/release/WormsWMD-macOS-Fix-VERSION/
    build/release/WormsWMD-macOS-Fix-VERSION.zip
    build/release/WormsWMD-macOS-Fix-VERSION.zip.sha256
EOF
}

sanitize_version() {
    local value="$1"

    value="${value//[^A-Za-z0-9._-]/-}"
    if [[ -z "$value" ]] || [[ "$value" == "." ]] || [[ "$value" == ".." ]]; then
        value="manual"
    fi

    printf '%s\n' "$value"
}

detect_version() {
    if [[ -n "$VERSION" ]]; then
        sanitize_version "$VERSION"
        return 0
    fi

    if command -v git >/dev/null 2>&1; then
        if VERSION=$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null); then
            sanitize_version "$VERSION"
            return 0
        fi
    fi

    sanitize_version "$(date '+%Y%m%d-%H%M%S')"
}

copy_item() {
    local rel="$1"
    local src="$ROOT_DIR/$rel"
    local dest="$bundle_dir/$rel"
    local parent

    if [[ ! -e "$src" ]]; then
        return 0
    fi

    parent=$(dirname "$dest")
    mkdir -p "$parent"
    cp -R "$src" "$dest"
    COPIED_ITEMS+=("$rel")
}

write_release_info() {
    cat > "$bundle_dir/RELEASE_INFO.txt" << EOF
Worms W.M.D macOS Fix release bundle
====================================

Version: $release_version
Built: $(date '+%Y-%m-%d %H:%M:%S %Z')
Repository: https://github.com/cboyd0319/WormsWMD-macOS-Fix

Start here:
1. Open README_FIRST.txt.
2. Double-click "Worms W.M.D Fix.command".
3. Use option 5 in the launcher if you need a support bundle.

Verify before unzipping:
Download the matching .zip.sha256 file from the same GitHub release, then run:

    shasum -a 256 -c $bundle_name.zip.sha256

GitHub CLI users can also verify release provenance with:

    gh attestation verify $bundle_name.zip --repo cboyd0319/WormsWMD-macOS-Fix

This community bundle includes original project files only. It does not include
official game art, game binaries, save files, or user data.
EOF
    COPIED_ITEMS+=("RELEASE_INFO.txt")
}

make_zip() {
    local zip_path="$OUTPUT_DIR/$bundle_name.zip"

    rm -f "$zip_path" "$zip_path.sha256"

    if command -v zip >/dev/null 2>&1; then
        (
            cd "$OUTPUT_DIR"
            COPYFILE_DISABLE=1 zip -X -qry "$zip_path" "$bundle_name"
        )
    elif command -v ditto >/dev/null 2>&1; then
        (
            cd "$OUTPUT_DIR"
            COPYFILE_DISABLE=1 ditto -c -k --keepParent "$bundle_name" "$zip_path"
        )
    else
        worms_print_error "Neither ditto nor zip is available; cannot create zip archive."
        exit 1
    fi

    shasum -a 256 "$zip_path" > "$zip_path.sha256"
    worms_print_success "Release zip: $zip_path"
    worms_print_success "Checksum: $zip_path.sha256"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                worms_print_error "--output-dir requires a directory."
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --version)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                worms_print_error "--version requires a value."
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        --skip-zip)
            SKIP_ZIP=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            worms_print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

release_version=$(detect_version)
bundle_name="WormsWMD-macOS-Fix-$release_version"
bundle_dir="$OUTPUT_DIR/$bundle_name"

if [[ "$bundle_name" == "WormsWMD-macOS-Fix-" ]]; then
    worms_print_error "Refusing to build a release bundle with an empty version."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$bundle_dir"
mkdir -p "$bundle_dir"

for rel in \
    "Worms W.M.D Fix.command" \
    "Install Fix.command" \
    "fix_worms_wmd.sh" \
    "install.sh" \
    "README_FIRST.txt" \
    "README.md" \
    "SUPPORT.md" \
    "STEAM_POST.md" \
    "ATTRIBUTIONS.md" \
    "SECURITY.md" \
    "CONTRIBUTING.md" \
    "CHANGELOG.md" \
    "LICENSE" \
    "TEAM17_DEVELOPER_REPORT.md" \
    "assets" \
    "dist" \
    "docs" \
    "scripts" \
    "src" \
    "tools"; do
    copy_item "$rel"
done

write_release_info

chmod +x \
    "$bundle_dir/Worms W.M.D Fix.command" \
    "$bundle_dir/Install Fix.command" \
    "$bundle_dir/fix_worms_wmd.sh" \
    "$bundle_dir/install.sh" 2>/dev/null || true

if [[ -d "$bundle_dir/scripts" ]]; then
    find "$bundle_dir/scripts" -type f -name "*.sh" -exec chmod +x {} +
fi
if [[ -d "$bundle_dir/tools" ]]; then
    find "$bundle_dir/tools" -type f -name "*.sh" -exec chmod +x {} +
fi

worms_write_manifest "$bundle_dir" "$bundle_dir/RELEASE_MANIFEST.tsv" "${COPIED_ITEMS[@]}"
worms_verify_manifest "$bundle_dir" "$bundle_dir/RELEASE_MANIFEST.tsv"

worms_print_success "Release folder: $bundle_dir"
worms_print_success "Manifest: $bundle_dir/RELEASE_MANIFEST.tsv"

if ! $SKIP_ZIP; then
    make_zip
fi
