#!/bin/bash
#
# Regression checks for save backup completeness.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
    printf 'save backup regression check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-save-backup.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

test_home="$tmp_dir/home"
backup_dir="$tmp_dir/backups"
team17_only_home="$tmp_dir/team17-only-home"
team17_only_backup_dir="$tmp_dir/team17-only-backups"
team17_dir="$test_home/Library/Application Support/Team17"
steam_dir="$test_home/Library/Application Support/Steam/userdata/123456/327030"
team17_only_dir="$team17_only_home/Library/Application Support/Team17"

mkdir -p "$team17_dir" "$steam_dir" "$team17_only_dir"
printf 'team17 hidden\n' > "$team17_dir/.hidden-team17"
printf 'team17 visible\n' > "$team17_dir/visible-team17"
printf 'steam hidden\n' > "$steam_dir/.hidden-steam"
printf 'steam visible\n' > "$steam_dir/visible-steam"
printf 'team17 only\n' > "$team17_only_dir/visible-team17"

HOME="$team17_only_home" BACKUP_DIR="$team17_only_backup_dir" "$ROOT_DIR/tools/backup_saves.sh" --backup >/dev/null \
    || fail "Team17-only save backup failed when Steam saves were absent"

HOME="$test_home" BACKUP_DIR="$backup_dir" "$ROOT_DIR/tools/backup_saves.sh" --backup >/dev/null

archive=$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type f -name 'saves-*.tar.gz' -print -quit)
[[ -n "$archive" ]] || fail "save backup archive was not created"

listing="$tmp_dir/listing.txt"
tar -tzf "$archive" | sort > "$listing"

for expected in \
    './Team17/.hidden-team17' \
    './Team17/visible-team17' \
    './Steam/123456/.hidden-steam' \
    './Steam/123456/visible-steam' \
    './MANIFEST.tsv'; do
    if ! grep -Fxq "$expected" "$listing"; then
        fail "archive is missing $expected"
    fi
done

printf 'corrupt team17\n' > "$team17_dir/visible-team17"
printf 'stale team17\n' > "$team17_dir/stale-team17"
printf 'corrupt steam\n' > "$steam_dir/visible-steam"
printf 'stale steam\n' > "$steam_dir/stale-steam"

HOME="$test_home" BACKUP_DIR="$backup_dir" WORMSWMD_RESTORE_ASSUME_YES=1 \
    "$ROOT_DIR/tools/backup_saves.sh" --restore "$archive" >/dev/null \
    || fail "save restore failed"

grep -Fxq 'team17 visible' "$team17_dir/visible-team17" \
    || fail "Team17 save file was not restored from backup"
grep -Fxq 'steam visible' "$steam_dir/visible-steam" \
    || fail "Steam save file was not restored from backup"
[[ ! -e "$team17_dir/stale-team17" ]] \
    || fail "Team17 restore left a file that was absent from the backup"
[[ ! -e "$steam_dir/stale-steam" ]] \
    || fail "Steam restore left a file that was absent from the backup"

alias_home="$tmp_dir/alias-home"
alias_root="$tmp_dir/alias-archive-root"
alias_archive="$tmp_dir/alias-save.tar.gz"
mkdir -p "$alias_home/Library/Application Support/Team17" "$alias_root/Team17"
printf 'original alias target\n' > "$alias_home/Library/Application Support/Team17/save.dat"
printf 'malicious duplicate\n' > "$alias_root/Team17/save.dat"
(
    cd "$alias_root"
    tar -czf "$alias_archive" Team17/save.dat Team17//save.dat
)
if HOME="$alias_home" WORMSWMD_RESTORE_ASSUME_YES=1 \
    "$ROOT_DIR/tools/backup_saves.sh" --restore "$alias_archive" >/dev/null 2>&1; then
    fail "save restore accepted canonically duplicate archive members"
fi
grep -Fxq 'original alias target' "$alias_home/Library/Application Support/Team17/save.dat" \
    || fail "duplicate-member save archive modified existing saves"

newline_home="$tmp_dir/newline-home"
newline_root="$tmp_dir/newline-archive-root"
newline_archive="$tmp_dir/newline-save.tar.gz"
newline_source="$newline_root/Team17/visible"$'\nTeam17'
mkdir -p "$newline_home/Library/Application Support/Team17" "$newline_source"
printf 'hidden newline save\n' > "$newline_source/injected.dat"
(
    cd "$newline_root"
    tar -czf "$newline_archive" Team17
)
if HOME="$newline_home" WORMSWMD_RESTORE_ASSUME_YES=1 \
    "$ROOT_DIR/tools/backup_saves.sh" --restore "$newline_archive" >/dev/null 2>&1; then
    fail "save restore accepted an archive path containing a newline"
fi

printf 'Save backup regression check passed.\n'
