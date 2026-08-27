#!/bin/bash
#
# Regression checks for issue #10 backup progress and diagnostics reporting.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/logging.sh"

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

ln -s missing "$tmp_dir/dangling.tar.gz"
unique_dangling=$(worms_unique_path "$tmp_dir/dangling" ".tar.gz")
if [[ "$unique_dangling" != "$tmp_dir/dangling-1.tar.gz" ]]; then
    fail "unique path reused a dangling symlink target"
fi

(
    HOME="$tmp_dir/home"
    LOG_DIR=""
    LOG_FILE=""
    worms_prepare_log_file "fix_worms_wmd"
    first_log="$LOG_FILE"
    touch "$first_log"
    LOG_FILE=""
    worms_prepare_log_file "fix_worms_wmd"
    second_log="$LOG_FILE"
    [[ "$first_log" != "$second_log" ]]
) || fail "default log path generation can reuse an existing log path"

(
    HOME="$tmp_dir/log-dir-home"
    mkdir -p "$HOME/Library/Logs"
    LOG_DIR="$HOME/Library/Logs/../OutsideLogs"
    LOG_FILE=""
    set +e
    worms_prepare_log_file "fix_worms_wmd" >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || exit 1
    [[ ! -e "$HOME/Library/OutsideLogs" ]]
) || fail "rejected LOG_DIR created a directory outside ~/Library/Logs"

(
    HOME="$tmp_dir/log-file-home"
    mkdir -p "$HOME/Library/Logs"
    LOG_DIR=""
    LOG_FILE="$HOME/Library/Logs/../OutsideLogFile/fix.log"
    set +e
    worms_prepare_log_file "fix_worms_wmd" >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || exit 1
    [[ ! -e "$HOME/Library/OutsideLogFile" ]]
) || fail "rejected LOG_FILE created a directory outside ~/Library/Logs"

(
    HOME="$tmp_dir/safe-nested-log-home"
    mkdir -p "$HOME/Library/Logs"
    LOG_DIR=""
    LOG_FILE="$HOME/Library/Logs/WormsWMD-Fix/Nested/fix.log"
    worms_prepare_log_file "fix_worms_wmd" >/dev/null 2>&1
    [[ "$LOG_FILE" == "$HOME/Library/Logs/WormsWMD-Fix/Nested/fix.log" ]]
    [[ -d "$HOME/Library/Logs/WormsWMD-Fix/Nested" ]]
) || fail "safe nested LOG_FILE under ~/Library/Logs was rejected"

(
    HOME="$tmp_dir/hardlinked-log-home"
    mkdir -p "$HOME/Library/Logs"
    outside_log_peer="$HOME/outside-log-peer.txt"
    hardlinked_log="$HOME/Library/Logs/hardlinked.log"
    printf 'outside peer\n' > "$outside_log_peer"
    ln "$outside_log_peer" "$hardlinked_log"
    LOG_DIR=""
    LOG_FILE="$hardlinked_log"
    set +e
    worms_prepare_log_file "fix_worms_wmd" >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || exit 1
) || fail "hardlinked LOG_FILE was accepted"

printf 'Issue #10 regression check passed.\n'
