#!/bin/bash
# Install the repository-local, checksum-pinned Kingfisher pre-commit hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"
HOOKS_DIR="$ROOT_DIR/.githooks"
KINGFISHER_VERSION="2.0.0"
KINGFISHER_TEMP_DIR=""
ALLOW_REVIEWED_COMMIT=""

cleanup_kingfisher_temp() {
    if [[ -n "$KINGFISHER_TEMP_DIR" ]]; then
        rm -rf "$KINGFISHER_TEMP_DIR"
    fi
}

usage() {
    printf '%s\n' \
        "Install the WormsWMD repository's enforced pre-commit hooks." \
        "" \
        "USAGE:" \
        "    ./tools/install_git_hooks.sh [--allow-reviewed-commit SHA]" \
        "    ./tools/install_git_hooks.sh --check" \
        "    ./tools/install_git_hooks.sh --uninstall" \
        "    ./tools/install_git_hooks.sh --purge"
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

file_sha256() {
    local shasum_bin

    shasum_bin=$(shasum_command)
    "$shasum_bin" -a 256 "$1" | awk '{print $1}'
}

shasum_command() {
    case "${WORMSWMD_HOOK_TEST_MODE:-}" in
        1|true|TRUE|yes|YES)
            if [[ -n "${WORMSWMD_TEST_SHASUM_BIN:-}" ]] && [[ -x "$WORMSWMD_TEST_SHASUM_BIN" ]]; then
                printf '%s\n' "$WORMSWMD_TEST_SHASUM_BIN"
                return 0
            fi
            ;;
    esac

    [[ -x /usr/bin/shasum ]] || {
        printf '%s\n' "ERROR: /usr/bin/shasum is required for Kingfisher verification." >&2
        return 1
    }
    printf '%s\n' /usr/bin/shasum
}

uname_command() {
    case "${WORMSWMD_HOOK_TEST_MODE:-}" in
        1|true|TRUE|yes|YES)
            if [[ -n "${WORMSWMD_TEST_UNAME_BIN:-}" ]] && [[ -x "$WORMSWMD_TEST_UNAME_BIN" ]]; then
                printf '%s\n' "$WORMSWMD_TEST_UNAME_BIN"
                return 0
            fi
            ;;
    esac

    [[ -x /usr/bin/uname ]] || {
        printf '%s\n' "ERROR: /usr/bin/uname is required for Kingfisher platform selection." >&2
        return 1
    }
    printf '%s\n' /usr/bin/uname
}

check_installation() {
    local hooks_path
    local binary
    local record
    local expected_binary_sha256
    local actual_binary_sha256

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
    record=$(platform_asset)
    expected_binary_sha256=${record##*$'\t'}
    actual_binary_sha256=$(file_sha256 "$binary")
    [[ "$actual_binary_sha256" == "$expected_binary_sha256" ]] || {
        printf '%s\n' \
            "ERROR: Installed Kingfisher does not match the pinned executable digest." \
            "Run ./tools/install_git_hooks.sh from a reviewed checkout to reinstall it." >&2
        return 1
    }
    printf '%s\n' "Git hooks and Kingfisher $KINGFISHER_VERSION are installed."
}

ensure_trusted_checkout() {
    local head_commit
    local upstream_main
    local origin_url

    head_commit=$(git -C "$ROOT_DIR" rev-parse HEAD)
    if ! git -C "$ROOT_DIR" diff --quiet -- \
        || ! git -C "$ROOT_DIR" diff --cached --quiet --; then
        printf '%s\n' "ERROR: Refusing to install hooks from a checkout with tracked changes." >&2
        return 1
    fi

    upstream_main=$(git -C "$ROOT_DIR" rev-parse refs/remotes/origin/main 2>/dev/null || true)
    origin_url=$(git -C "$ROOT_DIR" config --get remote.origin.url 2>/dev/null || true)
    case "$origin_url" in
        https://github.com/cboyd0319/WormsWMD-macOS-Fix|https://github.com/cboyd0319/WormsWMD-macOS-Fix.git|git@github.com:cboyd0319/WormsWMD-macOS-Fix|git@github.com:cboyd0319/WormsWMD-macOS-Fix.git|ssh://git@github.com/cboyd0319/WormsWMD-macOS-Fix|ssh://git@github.com/cboyd0319/WormsWMD-macOS-Fix.git)
            if [[ -n "$upstream_main" && "$head_commit" == "$upstream_main" ]]; then
                return 0
            fi
            ;;
    esac

    if [[ -n "$ALLOW_REVIEWED_COMMIT" ]]; then
        if [[ ! "$ALLOW_REVIEWED_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
            printf '%s\n' "ERROR: --allow-reviewed-commit requires a full lowercase commit ID." >&2
            return 1
        fi
        if [[ "$ALLOW_REVIEWED_COMMIT" != "$head_commit" ]]; then
            printf 'ERROR: Reviewed commit does not match HEAD: expected %s, found %s.\n' \
                "$ALLOW_REVIEWED_COMMIT" "$head_commit" >&2
            return 1
        fi
        printf 'Installing hooks from explicitly reviewed commit: %s\n' "$head_commit"
        return 0
    fi

    printf '%s\n' \
        "ERROR: Refusing to install hooks from an unreviewed checkout." \
        "Use reviewed origin/main, or pass --allow-reviewed-commit $head_commit after reviewing this exact commit." >&2
    return 1
}

platform_asset() {
    local os_name
    local architecture
    local uname_bin

    uname_bin=$(uname_command)
    os_name=$("$uname_bin" -s)
    architecture=$("$uname_bin" -m)
    case "$os_name:$architecture" in
        Darwin:arm64)
            printf '%s\t%s\t%s\n' \
                "kingfisher-darwin-arm64.tgz" \
                "6987b7f3e1f38c2f647523bf90fc207532dcf9cdf571936f9f10ab30b46c3754" \
                "bcda56855b5aee9e868d8f6d45c89c84a77ed1d15180cbd28ebc6b17c1d55ffb"
            ;;
        Darwin:x86_64)
            printf '%s\t%s\t%s\n' \
                "kingfisher-darwin-x64.tgz" \
                "de54730312d11b42cb306e6b3b5979d08615b1c9d39359e32a6b1d60839501c7" \
                "0013b6f7709fbd65408c8b0debd5211365bb0ce123912aaec23065a0627325fe"
            ;;
        Linux:x86_64)
            printf '%s\t%s\t%s\n' \
                "kingfisher-linux-x64.tgz" \
                "d30d71f82e25e8c024f98cce3258c90e17b5be31d0fdb6f30b438d2fac1f130b" \
                "e5aa138eb67931b5520cedcde0ed605516ad4f3251c56f6cf0d93bb885782f1c"
            ;;
        Linux:arm64|Linux:aarch64)
            printf '%s\t%s\t%s\n' \
                "kingfisher-linux-arm64.tgz" \
                "ccb230322aac4b3fa16a35d8e3b86680b8cb7f06ebf64f3c81cec8be7b2024af" \
                "a3ffa17d13feb7236fc2a268ad1fb4b9e17059033c9a0aeb358c79676dd6e66b"
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
    local expected_binary_sha256
    local download_url
    local temporary_directory
    local downloaded_archive
    local archive
    local candidate
    local binary
    local shasum_bin

    record=$(platform_asset)
    asset=${record%%$'\t'*}
    record=${record#*$'\t'}
    expected_sha256=${record%%$'\t'*}
    expected_binary_sha256=${record##*$'\t'}
    download_url="https://github.com/mongodb/kingfisher/releases/download/v${KINGFISHER_VERSION}/${asset}"
    temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-kingfisher.XXXXXX")
    KINGFISHER_TEMP_DIR="$temporary_directory"
    trap cleanup_kingfisher_temp EXIT
    downloaded_archive="$temporary_directory/.download-$asset"
    archive="$temporary_directory/$asset"

    curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
        --retry 3 --retry-delay 1 --retry-connrefused --max-time 120 \
        --max-filesize $((64 * 1024 * 1024)) \
        --output "$downloaded_archive" "$download_url"
    shasum_bin=$(shasum_command)
    printf '%s  %s\n' "$expected_sha256" "$downloaded_archive" | "$shasum_bin" -a 256 -c -
    worms_copy_and_inspect_archive \
        "$downloaded_archive" "$archive" kingfisher "$expected_sha256" --quiet
    tar -xzf "$archive" -C "$temporary_directory" kingfisher

    candidate="$temporary_directory/kingfisher"
    [[ -x "$candidate" ]] || {
        printf '%s\n' "ERROR: Downloaded Kingfisher is not executable." >&2
        return 1
    }
    [[ "$("$candidate" --version 2>/dev/null)" == "kingfisher $KINGFISHER_VERSION" ]] || {
        printf '%s\n' "ERROR: Downloaded Kingfisher failed its version check." >&2
        return 1
    }
    [[ "$(file_sha256 "$candidate")" == "$expected_binary_sha256" ]] || {
        printf '%s\n' "ERROR: Downloaded Kingfisher executable digest does not match the pin." >&2
        return 1
    }
    binary=$(installed_binary)
    mkdir -p "$(dirname "$binary")"
    install -m 0755 "$candidate" "$binary"
    rm -rf "$temporary_directory"
    KINGFISHER_TEMP_DIR=""
    trap - EXIT
}

action="install"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --allow-reviewed-commit)
            [[ "$#" -ge 2 ]] || {
                usage >&2
                exit 2
            }
            ALLOW_REVIEWED_COMMIT="$2"
            shift 2
            ;;
        --check|--uninstall|--purge)
            [[ "$action" == "install" ]] || {
                usage >&2
                exit 2
            }
            action="${1#--}"
            shift
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
done

if [[ "$action" != "install" && -n "$ALLOW_REVIEWED_COMMIT" ]]; then
    usage >&2
    exit 2
fi

case "$action" in
    install)
        ensure_trusted_checkout
        ;;
    check)
        check_installation
        exit
        ;;
    uninstall)
        if [[ "$(git -C "$ROOT_DIR" config --local --get core.hooksPath 2>/dev/null || true)" == ".githooks" ]]; then
            git -C "$ROOT_DIR" config --local --unset core.hooksPath
        fi
        printf '%s\n' "Repository Git hooks are disabled; the cached scanner was retained."
        exit
        ;;
    purge)
        if [[ "$(git -C "$ROOT_DIR" config --local --get core.hooksPath 2>/dev/null || true)" == ".githooks" ]]; then
            git -C "$ROOT_DIR" config --local --unset core.hooksPath
        fi
        binary=$(installed_binary)
        if [[ -d "$binary" ]]; then
            printf 'ERROR: Refusing to purge a directory at the scanner path: %s\n' "$binary" >&2
            exit 1
        fi
        printf 'Removing cached scanner: %s\n' "$binary"
        rm -f -- "$binary"
        printf '%s\n' "Repository Git hooks and cached scanner are removed."
        exit
        ;;
esac

installed=$(installed_binary)
platform_record=$(platform_asset)
installed_expected_sha256=${platform_record##*$'\t'}
if [[ ! -x "$installed" ]] \
    || [[ "$("$installed" --version 2>/dev/null || true)" != "kingfisher $KINGFISHER_VERSION" ]] \
    || [[ "$(file_sha256 "$installed" 2>/dev/null || true)" != "$installed_expected_sha256" ]]; then
    install_kingfisher
fi
git -C "$ROOT_DIR" config --local core.hooksPath .githooks
check_installation
