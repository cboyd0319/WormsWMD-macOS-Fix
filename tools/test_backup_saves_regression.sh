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

printf 'Save backup regression check passed.\n'
