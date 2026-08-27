#!/bin/bash
#
# Regression checks for save backup completeness.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

extract_function() {
    local function_name="$1"
    local source_file="$2"

    awk -v signature="^${function_name}\\(\\)" '
        $0 ~ signature {inside=1}
        inside {print}
        inside && /^}/ {exit}
    ' "$source_file"
}

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

no_python_repo="$tmp_dir/no-python-repo"
mkdir -p "$no_python_repo/tools" "$no_python_repo/scripts"
cp "$ROOT_DIR/tools/backup_saves.sh" "$no_python_repo/tools/backup_saves.sh"
cp "$ROOT_DIR/scripts/common.sh" "$no_python_repo/scripts/common.sh"
cp "$ROOT_DIR/scripts/ui.sh" "$no_python_repo/scripts/ui.sh"
printf '\nworms_python3() { return 1; }\n' >> "$no_python_repo/scripts/common.sh"
chmod +x "$no_python_repo/tools/backup_saves.sh"
no_python_backup="$no_python_repo/tools/backup_saves.sh"

if ! "$ROOT_DIR/tools/backup_saves.sh" --help | grep -Fq -- '--max-expanded-size SIZE'; then
    fail "save restore help does not document the bounded expanded-size override"
fi
if ! "$ROOT_DIR/tools/backup_saves.sh" --help | grep -Fq -- '--allow-external-steam-root PATH'; then
    fail "save restore help does not document exact external Steam-root trust"
fi
if ! HOME="$test_home" BACKUP_DIR="$backup_dir" \
    "$no_python_backup" --list >/dev/null; then
    fail "listing save backups unnecessarily requires Python"
fi

archive=$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type f -name 'saves-*.tar.gz' -print -quit)
[[ -n "$archive" ]] || fail "save backup archive was not created"

no_python_home="$tmp_dir/no-python-home"
mkdir -p "$no_python_home/Library/Application Support/Team17"
printf 'must remain unchanged\n' > "$no_python_home/Library/Application Support/Team17/save.dat"
if HOME="$no_python_home" WORMSWMD_RESTORE_ASSUME_YES=1 \
    "$no_python_backup" --restore "$archive" >/dev/null 2>&1; then
    fail "save restore proceeded without a compatible Python interpreter"
fi
grep -Fxq 'must remain unchanged' "$no_python_home/Library/Application Support/Team17/save.dat" \
    || fail "save restore without Python modified existing saves"

if HOME="$no_python_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$archive" --max-expanded-size 1G >/dev/null 2>&1; then
    fail "save restore accepted a size override without explicit --yes"
fi
if HOME="$no_python_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$archive" --yes --max-expanded-size 9G >/dev/null 2>&1; then
    fail "save restore accepted a size override above the 8 GiB limit"
fi

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

invalid_id_home="$tmp_dir/invalid-id-home"
invalid_id_root="$tmp_dir/invalid-id-root"
invalid_id_archive="$tmp_dir/invalid-id.tar.gz"
mkdir -p "$invalid_id_home/Library/Application Support/Steam/userdata" \
    "$invalid_id_root/Steam/not-a-user"
printf 'invalid user save\n' > "$invalid_id_root/Steam/not-a-user/save.dat"
tar -czf "$invalid_id_archive" -C "$invalid_id_root" Steam
if HOME="$invalid_id_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$invalid_id_archive" --yes >/dev/null 2>&1; then
    fail "save restore accepted a non-numeric Steam user ID"
fi
[[ ! -e "$invalid_id_home/Library/Application Support/Steam/userdata/not-a-user/327030/save.dat" ]] \
    || fail "non-numeric Steam restore mutated a destination"

escaping_home="$tmp_dir/escaping-home"
escaping_root="$tmp_dir/escaping-root"
escaping_archive="$tmp_dir/escaping.tar.gz"
escaping_outside_user="$tmp_dir/escaping-outside-user"
mkdir -p "$escaping_home/Library/Application Support/Steam/userdata" \
    "$escaping_root/Steam/777" "$escaping_outside_user/327030"
ln -s "$escaping_outside_user" \
    "$escaping_home/Library/Application Support/Steam/userdata/777"
printf 'outside original\n' > "$escaping_outside_user/327030/original.dat"
printf 'archive replacement\n' > "$escaping_root/Steam/777/save.dat"
tar -czf "$escaping_archive" -C "$escaping_root" Steam
if HOME="$escaping_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$escaping_archive" --yes >/dev/null 2>&1; then
    fail "save restore followed an intermediate Steam-user symlink"
fi
grep -Fxq 'outside original' "$escaping_outside_user/327030/original.dat" \
    || fail "escaping Steam-user restore modified outside data"
[[ ! -e "$escaping_outside_user/327030/save.dat" ]] \
    || fail "escaping Steam-user restore installed outside data"

internal_home="$tmp_dir/internal-home"
internal_root="$tmp_dir/internal-root"
internal_archive="$tmp_dir/internal.tar.gz"
internal_userdata="$internal_home/Library/Application Support/Steam/userdata"
internal_target="$internal_userdata/relocated-327030"
mkdir -p "$internal_userdata/888" "$internal_target" "$internal_root/Steam/888"
ln -s ../relocated-327030 "$internal_userdata/888/327030"
printf 'internal old\n' > "$internal_target/old.dat"
printf 'internal restored\n' > "$internal_root/Steam/888/save.dat"
tar -czf "$internal_archive" -C "$internal_root" Steam
HOME="$internal_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$internal_archive" --yes >/dev/null \
    || fail "save restore rejected an internal contained 327030 link"
[[ -L "$internal_userdata/888/327030" ]] \
    || fail "internal contained restore replaced the 327030 link itself"
grep -Fxq 'internal restored' "$internal_target/save.dat" \
    || fail "internal contained restore did not update its canonical target"
[[ ! -e "$internal_target/old.dat" ]] \
    || fail "internal contained restore left stale target data"

external_home="$tmp_dir/external-home"
external_root="$tmp_dir/external-root"
external_archive="$tmp_dir/external.tar.gz"
external_userdata="$external_home/Library/Application Support/Steam/userdata"
external_target="$tmp_dir/external-volume/Worms-WMD-327030"
mkdir -p "$external_userdata/999" "$external_target" "$external_root/Steam/999"
ln -s "$external_target" "$external_userdata/999/327030"
external_target_real=$(cd "$external_target" && pwd -P)
printf 'external old\n' > "$external_target/old.dat"
printf 'external restored\n' > "$external_root/Steam/999/save.dat"
tar -czf "$external_archive" -C "$external_root" Steam
if HOME="$external_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$external_archive" \
    --allow-external-steam-root "$external_target_real" >/dev/null 2>&1; then
    fail "external Steam-root trust did not require explicit --yes"
fi
if HOME="$external_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$external_archive" --yes >/dev/null 2>&1; then
    fail "save restore accepted an external 327030 target without exact opt-in"
fi
grep -Fxq 'external old' "$external_target/old.dat" \
    || fail "untrusted external restore modified existing data"
if HOME="$external_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$external_archive" --yes \
    --allow-external-steam-root "$(dirname "$external_target_real")" >/dev/null 2>&1; then
    fail "save restore accepted a broad external Steam parent"
fi
if ! external_output=$(HOME="$external_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$external_archive" --yes \
    --allow-external-steam-root "$external_target_real" 2>&1); then
    fail "save restore rejected its exact canonical external 327030 target: $external_output"
fi
grep -Fq "External Steam restore target: $external_target_real" <<< "$external_output" \
    || fail "external Steam restore did not preview the exact canonical target"
[[ -L "$external_userdata/999/327030" ]] \
    || fail "external restore replaced the trusted 327030 link itself"
grep -Fxq 'external restored' "$external_target/save.dat" \
    || fail "external restore did not update the exact trusted target"
[[ ! -e "$external_target/old.dat" ]] \
    || fail "external restore left stale target data"
if HOME="$external_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$external_archive" --yes >/dev/null 2>&1; then
    fail "external Steam-root trust persisted beyond one invocation"
fi

missing_home="$tmp_dir/missing-external-home"
missing_root="$tmp_dir/missing-external-root"
missing_archive="$tmp_dir/missing-external.tar.gz"
missing_userdata="$missing_home/Library/Application Support/Steam/userdata"
missing_target="$tmp_dir/missing-volume/Worms-WMD-327030"
mkdir -p "$missing_userdata/1000" "$missing_root/Steam/1000"
ln -s "$missing_target" "$missing_userdata/1000/327030"
printf 'missing restored\n' > "$missing_root/Steam/1000/save.dat"
tar -czf "$missing_archive" -C "$missing_root" Steam
if HOME="$missing_home" "$ROOT_DIR/tools/backup_saves.sh" \
    --restore "$missing_archive" --yes \
    --allow-external-steam-root "$missing_target" >/dev/null 2>&1; then
    fail "save restore accepted a missing external volume target"
fi

archive_failure_repo="$tmp_dir/archive-failure-repo"
archive_failure_home="$tmp_dir/archive-failure-home"
mkdir -p "$archive_failure_repo/tools" "$archive_failure_repo/scripts" \
    "$archive_failure_home/Library/Application Support/Team17"
cp "$ROOT_DIR/tools/backup_saves.sh" "$archive_failure_repo/tools/backup_saves.sh"
cp "$ROOT_DIR/tools/inspect_archive.py" "$archive_failure_repo/tools/inspect_archive.py"
cp "$ROOT_DIR/scripts/common.sh" "$archive_failure_repo/scripts/common.sh"
cp "$ROOT_DIR/scripts/ui.sh" "$archive_failure_repo/scripts/ui.sh"
printf '\nworms_copy_and_inspect_archive() { return 1; }\n' \
    >> "$archive_failure_repo/scripts/common.sh"
chmod +x "$archive_failure_repo/tools/backup_saves.sh"
printf 'archive failure original\n' \
    > "$archive_failure_home/Library/Application Support/Team17/save.dat"
if HOME="$archive_failure_home" "$archive_failure_repo/tools/backup_saves.sh" \
    --restore "$archive" --yes >/dev/null 2>&1; then
    fail "save restore ignored an archive-copy failure"
fi
grep -Fxq 'archive failure original' \
    "$archive_failure_home/Library/Application Support/Team17/save.dat" \
    || fail "archive-copy failure modified existing saves"

save_functions="$tmp_dir/save-functions.sh"
for function_name in \
    steam_process_state_with ensure_steam_stopped queue_save_transaction \
    verify_save_tree_copy cleanup_save_transaction_stages \
    ensure_save_target_parent prepare_save_tree_stage \
    prepare_save_transactions \
    rollback_save_transactions finalize_save_transactions \
    apply_save_transactions; do
    extract_function "$function_name" "$ROOT_DIR/tools/backup_saves.sh" \
        >> "$save_functions"
done
# shellcheck disable=SC1090
source "$save_functions"
# shellcheck disable=SC2034
RED=""
# shellcheck disable=SC2034
YELLOW=""
# shellcheck disable=SC2034
NC=""

fake_pgrep="$tmp_dir/fake-pgrep"
cat > "$fake_pgrep" <<'STUB'
#!/bin/bash
case "${FAKE_PGREP_STATE:-stopped}" in
    running)
        [[ "${2:-}" == "steam_osx" ]]
        ;;
    stopped)
        exit 1
        ;;
    unknown)
        exit 2
        ;;
esac
STUB
chmod +x "$fake_pgrep"
[[ "$(FAKE_PGREP_STATE=running steam_process_state_with "$fake_pgrep")" == "running" ]] \
    || fail "Steam process classifier missed a positive steam_osx result"
[[ "$(FAKE_PGREP_STATE=stopped steam_process_state_with "$fake_pgrep")" == "stopped" ]] \
    || fail "Steam process classifier did not distinguish no match"
[[ "$(FAKE_PGREP_STATE=unknown steam_process_state_with "$fake_pgrep")" == "unknown" ]] \
    || fail "Steam process classifier treated a detection error as stopped"

steam_state_file="$tmp_dir/steam-state"
printf '%s\n' running > "$steam_state_file"
# shellcheck disable=SC2329
steam_process_state() {
    local state
    state=$(cat "$steam_state_file")
    if [[ "$state" == "running" ]]; then
        printf '%s\n' stopped > "$steam_state_file"
    fi
    printf '%s\n' "$state"
}
# shellcheck disable=SC2329
restore_assume_yes() { return 1; }
wait_for_steam_close() { return 0; }
ensure_steam_stopped >/dev/null \
    || fail "interactive Steam close and successful recheck were rejected"

# shellcheck disable=SC2329
steam_process_state() { printf '%s\n' running; }
restore_assume_yes() { return 0; }
if ensure_steam_stopped >/dev/null 2>&1; then
    fail "unattended restore continued while Steam was positively running"
fi
steam_process_state() { printf '%s\n' unknown; }
ensure_steam_stopped >/dev/null \
    || fail "Steam detection failure was treated as proof of a running process"

# shellcheck disable=SC2034
reset_save_transaction_state() {
    RESTORE_TRANSACTION_ACTIVE=false
    RESTORE_TRANSACTION_COUNT=0
    RESTORE_SOURCE_DIRS=()
    RESTORE_TARGET_DIRS=()
    RESTORE_ALLOWED_ROOTS=()
    RESTORE_STAGE_DIRS=()
    RESTORE_RETAINED_DIRS=()
    RESTORE_HAD_OLD=()
    RESTORE_APPLIED=()
}

copy_failure_root="$tmp_dir/copy-failure"
mkdir -p "$copy_failure_root/source" "$copy_failure_root/target"
printf 'replacement\n' > "$copy_failure_root/source/save.dat"
printf 'original\n' > "$copy_failure_root/target/save.dat"
reset_save_transaction_state
queue_save_transaction "$copy_failure_root/source" "$copy_failure_root/target" "$copy_failure_root"
# shellcheck disable=SC2329
cp() { return 1; }
# shellcheck disable=SC2329
verify_restored_saves() { return 0; }
if prepare_save_transactions >/dev/null 2>&1; then
    unset -f cp
    fail "save transaction ignored a staging copy failure"
fi
unset -f cp
grep -Fxq original "$copy_failure_root/target/save.dat" \
    || fail "staging copy failure modified the original save tree"

# Restore production transaction functions after the copy-failure override.
# shellcheck disable=SC1090
source "$save_functions"
retention_failure_root="$tmp_dir/retention-failure"
mkdir -p "$retention_failure_root/source" "$retention_failure_root/target"
printf 'replacement\n' > "$retention_failure_root/source/save.dat"
printf 'original\n' > "$retention_failure_root/target/save.dat"
reset_save_transaction_state
queue_save_transaction \
    "$retention_failure_root/source" "$retention_failure_root/target" "$retention_failure_root"
prepare_save_transactions
# shellcheck disable=SC2329
mv() {
    if [[ "${2:-}" == */original ]]; then
        return 1
    fi
    command mv "$@"
}
if apply_save_transactions >/dev/null 2>&1; then
    unset -f mv
    fail "save transaction ignored an old-tree retention failure"
fi
unset -f mv
grep -Fxq original "$retention_failure_root/target/save.dat" \
    || fail "old-tree retention failure removed the original save tree"

# Restore production transaction functions after the retention-failure override.
# shellcheck disable=SC1090
source "$save_functions"
post_verify_root="$tmp_dir/post-verify-failure"
mkdir -p "$post_verify_root/source" "$post_verify_root/target"
printf 'replacement\n' > "$post_verify_root/source/save.dat"
printf 'original\n' > "$post_verify_root/target/save.dat"
reset_save_transaction_state
queue_save_transaction "$post_verify_root/source" "$post_verify_root/target" "$post_verify_root"
verify_count=0
# shellcheck disable=SC2329
verify_save_tree_copy() {
    verify_count=$((verify_count + 1))
    [[ "$verify_count" -eq 1 ]]
}
# shellcheck disable=SC2329
verify_restored_saves() { return 0; }
set +e
post_verify_output=$(prepare_save_transactions && apply_save_transactions 2>&1)
post_verify_status=$?
set -e
[[ "$post_verify_status" -ne 0 ]] \
    || fail "save transaction ignored post-publish verification failure"
grep -Fxq original "$post_verify_root/target/save.dat" \
    || fail "post-publish failure did not restore the original save tree"
[[ ! -e "$post_verify_root/target/replacement.dat" ]] \
    || fail "post-publish rollback retained replacement data"
grep -Fq 'Save restore rollback completed' <<< "$post_verify_output" \
    || fail "successful save rollback was not reported"

# Restore production functions, then make only the old-tree rollback move fail.
# shellcheck disable=SC1090
source "$save_functions"
rollback_failure_root="$tmp_dir/rollback-failure"
mkdir -p "$rollback_failure_root/source" "$rollback_failure_root/target"
printf 'replacement\n' > "$rollback_failure_root/source/save.dat"
printf 'original\n' > "$rollback_failure_root/target/save.dat"
reset_save_transaction_state
queue_save_transaction "$rollback_failure_root/source" "$rollback_failure_root/target" "$rollback_failure_root"
verify_count=0
# shellcheck disable=SC2329
verify_save_tree_copy() {
    verify_count=$((verify_count + 1))
    [[ "$verify_count" -eq 1 ]]
}
# shellcheck disable=SC2329
verify_restored_saves() { return 0; }
# shellcheck disable=SC2329
mv() {
    if [[ "${1:-}" == */original ]]; then
        return 1
    fi
    command mv "$@"
}
set +e
rollback_failure_output=$(prepare_save_transactions && apply_save_transactions 2>&1)
rollback_failure_status=$?
set -e
unset -f mv
[[ "$rollback_failure_status" -ne 0 ]] \
    || fail "save transaction reported success after rollback failure"
retained_original=$(find "$rollback_failure_root" -path '*/.target.restore-retained.*/original/save.dat' -print -quit)
[[ -n "$retained_original" ]] \
    || fail "rollback failure did not retain the original save tree"
grep -Fxq original "$retained_original" \
    || fail "retained rollback tree did not contain original data"
grep -Fq 'Save restore rollback failed' <<< "$rollback_failure_output" \
    || fail "rollback failure was not reported explicitly"

printf 'Save backup regression check passed.\n'
