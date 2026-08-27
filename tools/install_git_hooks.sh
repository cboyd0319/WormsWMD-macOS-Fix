#!/bin/bash
# Install the repository-local, checksum-pinned Kingfisher pre-commit hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$ROOT_DIR/.githooks"
KINGFISHER_VERSION="2.0.0"

usage() {
    printf '%s\n' \
        "Install the WormsWMD repository's enforced pre-commit hooks." \
        "" \
        "USAGE:" \
        "    ./tools/install_git_hooks.sh [--check|--uninstall]"
}

git_common_dir() {
    local directory
    directory=$(git -C "$ROOT_DIR" rev-parse --git-common-dir)
    if [[ "$directory" != /* ]]; then
        directory="$ROOT_DIR/$directory"
    fi
    printf '%s\n' "$directory"
}

installed_binary() {
    printf '%s/tools/kingfisher\n' "$(git_common_dir)"
}

check_installation() {
    local hooks_path
    local binary

    hooks_path=$(git -C "$ROOT_DIR" config --local --get core.hooksPath 2>/dev/null || true)
    [[ "$hooks_path" == ".githooks" ]] || {
        printf '%s\n' "ERROR: core.hooksPath is not configured for .githooks." >&2
        return 1
    }
    [[ -x "$HOOKS_DIR/pre-commit" ]] || {
        printf '%s\n' "ERROR: .githooks/pre-commit is not executable." >&2
        return 1
    }
    binary=$(installed_binary)
    [[ -x "$binary" ]] || {
        printf '%s\n' "ERROR: Pinned Kingfisher is not installed at $binary." >&2
        return 1
    }
    [[ "$("$binary" --version 2>/dev/null)" == "kingfisher $KINGFISHER_VERSION" ]] || {
        printf '%s\n' "ERROR: Installed Kingfisher version is not $KINGFISHER_VERSION." >&2
        return 1
    }
    printf '%s\n' "Git hooks and Kingfisher $KINGFISHER_VERSION are installed."
}

platform_asset() {
    local os_name
    local architecture

    os_name=$(uname -s)
    architecture=$(uname -m)
    case "$os_name:$architecture" in
        Darwin:arm64)
            printf '%s\t%s\n' \
                "kingfisher-darwin-arm64.tgz" \
                "6987b7f3e1f38c2f647523bf90fc207532dcf9cdf571936f9f10ab30b46c3754"
            ;;
        Darwin:x86_64)
            printf '%s\t%s\n' \
                "kingfisher-darwin-x64.tgz" \
                "de54730312d11b42cb306e6b3b5979d08615b1c9d39359e32a6b1d60839501c7"
            ;;
        Linux:x86_64)
            printf '%s\t%s\n' \
                "kingfisher-linux-x64.tgz" \
                "d30d71f82e25e8c024f98cce3258c90e17b5be31d0fdb6f30b438d2fac1f130b"
            ;;
        Linux:arm64|Linux:aarch64)
            printf '%s\t%s\n' \
                "kingfisher-linux-arm64.tgz" \
                "ccb230322aac4b3fa16a35d8e3b86680b8cb7f06ebf64f3c81cec8be7b2024af"
            ;;
        *)
            printf 'ERROR: Automatic Kingfisher installation does not support %s %s.\n' \
                "$os_name" "$architecture" >&2
            printf '%s\n' \
                "Install Kingfisher $KINGFISHER_VERSION manually, then rerun this command." >&2
            return 1
            ;;
    esac
}

install_kingfisher() {
    local record
    local asset
    local expected_sha256
    local download_url
    local temporary_directory
    local archive
    local binary

    record=$(platform_asset)
    asset=${record%%$'\t'*}
    expected_sha256=${record#*$'\t'}
    download_url="https://github.com/mongodb/kingfisher/releases/download/v${KINGFISHER_VERSION}/${asset}"
    temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-kingfisher.XXXXXX")
    trap 'rm -rf "$temporary_directory"' EXIT
    archive="$temporary_directory/$asset"

    curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
        --retry 3 --retry-delay 1 --retry-connrefused --max-time 120 \
        --output "$archive" "$download_url"
    printf '%s  %s\n' "$expected_sha256" "$archive" | shasum -a 256 -c -
    tar -xzf "$archive" -C "$temporary_directory" kingfisher

    binary=$(installed_binary)
    mkdir -p "$(dirname "$binary")"
    install -m 0755 "$temporary_directory/kingfisher" "$binary"
    [[ "$("$binary" --version 2>/dev/null)" == "kingfisher $KINGFISHER_VERSION" ]] || {
        printf '%s\n' "ERROR: Downloaded Kingfisher failed its version check." >&2
        return 1
    }
    rm -rf "$temporary_directory"
    trap - EXIT
}

case "${1:-}" in
    "")
        ;;
    --check)
        check_installation
        exit
        ;;
    --uninstall)
        if [[ "$(git -C "$ROOT_DIR" config --local --get core.hooksPath 2>/dev/null || true)" == ".githooks" ]]; then
            git -C "$ROOT_DIR" config --local --unset core.hooksPath
        fi
        printf '%s\n' "Repository Git hooks are disabled; the cached scanner was retained."
        exit
        ;;
    --help|-h)
        usage
        exit
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

installed=$(installed_binary)
if [[ ! -x "$installed" ]] \
    || [[ "$("$installed" --version 2>/dev/null || true)" != "kingfisher $KINGFISHER_VERSION" ]]; then
    install_kingfisher
fi
git -C "$ROOT_DIR" config --local core.hooksPath .githooks
check_installation
