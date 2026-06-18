#!/bin/bash
#
# Regression checks for issue #10 backup progress and diagnostics reporting.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'issue #10 regression check failed: %s\n' "$*" >&2
    exit 1
}

backup_block=$(
    awk '
        /print_step "Creating backup\.\.\."/ { in_block=1 }
        in_block { print }
        /print_step "Building AGL stub library\.\.\."/ { exit }
    ' "$ROOT_DIR/fix_worms_wmd.sh"
)

if ! grep -Fq 'Creating backup manifest (this can take a few minutes)...' <<< "$backup_block"; then
    fail "backup manifest creation has no explicit progress message"
fi

if grep -Fq "verify_game_backup_manifest \"\$BACKUP_DIR\"" <<< "$backup_block"; then
    fail "normal apply path still re-hashes the backup immediately after writing the manifest"
fi

restore_block=$(
    awk '
        /^do_restore\(\)/ { in_block=1 }
        /^do_fix\(\)/ && in_block { exit }
        in_block { print }
    ' "$ROOT_DIR/fix_worms_wmd.sh"
)

if ! grep -Fq 'Verifying backup manifest (this can take a few minutes)...' <<< "$restore_block"; then
    fail "restore path verifies backup manifests without an explicit progress message"
fi

if ! grep -Fq 'Verifying restored files...' <<< "$restore_block"; then
    fail "restore path verifies restored files without an explicit progress message"
fi

if grep -Fq '5.3.2 →' "$ROOT_DIR/fix_worms_wmd.sh"; then
    fail "Qt replacement status is hardcoded to say it upgraded from Qt 5.3.2"
fi

if ! awk '
    /^offer_steam_watcher\(\)/ { in_block=1 }
    /^# =/ && in_block { exit }
    in_block && /if \$FORCE/ { force_line=NR }
    in_block && /Would you like to be notified/ { offer_line=NR }
    END { exit !(force_line > 0 && offer_line > 0 && force_line < offer_line) }
' "$ROOT_DIR/fix_worms_wmd.sh"; then
    fail "force mode still prints the Steam watcher offer before returning"
fi

if ! grep -Fq 'latest_original_game_backup' "$ROOT_DIR/fix_worms_wmd.sh"; then
    fail "restore path does not prefer original backups over already-fixed backups"
fi

if ! grep -Fq 'Every backup found appears to already include the fix.' "$ROOT_DIR/fix_worms_wmd.sh"; then
    fail "restore path does not warn when only already-fixed backups are available"
fi

if grep -Fq 'grep -c "quarantine" || echo "0"' "$ROOT_DIR/tools/collect_diagnostics.sh"; then
    fail "diagnostics quarantine check still uses grep -c with an || echo fallback"
fi

diagnostics_output=$("$ROOT_DIR/tools/collect_diagnostics.sh")

if grep -Fq "Local package checksum mismatch" <<< "$diagnostics_output"; then
    fail "diagnostics still reports a false local Qt checksum mismatch"
fi

if ! grep -Fq "Local package checksum verified" <<< "$diagnostics_output"; then
    fail "diagnostics did not report the local Qt checksum as verified"
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-issue10.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

touch "$tmp_dir/archive.tar.gz"
unique_archive=$(worms_unique_path "$tmp_dir/archive" ".tar.gz")
if [[ "$unique_archive" != "$tmp_dir/archive-1.tar.gz" ]]; then
    fail "unique file path did not preserve the archive suffix"
fi

mkdir "$tmp_dir/backup"
unique_backup=$(worms_unique_path "$tmp_dir/backup")
if [[ "$unique_backup" != "$tmp_dir/backup-1" ]]; then
    fail "unique directory path did not add a numeric suffix"
fi

printf 'Issue #10 regression check passed.\n'
