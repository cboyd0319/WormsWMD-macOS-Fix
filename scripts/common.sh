#!/bin/bash
#
# common.sh - shared helpers for Worms W.M.D fix scripts and tools
#

worms_default_game_app() {
    printf '%s\n' "$HOME/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app"
}

worms_game_search_paths() {
    local steam_config line lib_path root found_path
    local system_applications_root="${WORMSWMD_TEST_APPLICATIONS_ROOT:-/Applications}"

    printf '%s\0' "$(worms_default_game_app)"
    printf '%s\0' "$system_applications_root/Worms W.M.D.app"
    printf '%s\0' "$system_applications_root/Worms WMD.app"
    printf '%s\0' "$HOME/Applications/Worms W.M.D.app"
    printf '%s\0' "$HOME/Applications/Worms WMD.app"
    printf '%s\0' "$HOME/Games/Worms W.M.D.app"
    printf '%s\0' "$HOME/Games/Worms WMD.app"
    printf '%s\0' "$HOME/GOG Games/Worms W.M.D/Worms W.M.D.app"
    printf '%s\0' "$HOME/GOG Games/Worms W.M.D.app"
    printf '%s\0' "$HOME/Library/Application Support/GOG.com/Games/Worms W.M.D/Worms W.M.D.app"

    for root in \
        "$system_applications_root" \
        "$HOME/Applications" \
        "$HOME/Games" \
        "$HOME/GOG Games" \
        "$HOME/Library/Application Support/GOG.com/Games"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r -d '' found_path; do
            printf '%s\0' "$found_path"
        done < <(find "$root" -mindepth 1 -maxdepth 2 -type d \( -name "Worms W.M.D.app" -o -name "Worms WMD.app" \) -print0 2>/dev/null)
    done

    steam_config="$HOME/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
    if [[ -f "$steam_config" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ \"path\"[[:space:]]*\"([^\"]+)\" ]]; then
                lib_path="${BASH_REMATCH[1]}"
                if [[ -d "$lib_path" ]]; then
                    printf '%s\0' "$lib_path/steamapps/common/WormsWMD/Worms W.M.D.app"
                fi
            fi
        done < "$steam_config"
    fi
}

worms_find_game_apps() {
    local path game existing
    local already_seen
    local found_games=()
    local unique_games=()

    while IFS= read -r -d '' path; do
        if [[ -d "$path" ]] && [[ -f "$path/Contents/MacOS/Worms W.M.D" ]]; then
            found_games+=("$path")
        fi
    done < <(worms_game_search_paths)

    if (( ${#found_games[@]} > 0 )); then
        for game in "${found_games[@]}"; do
            already_seen=false
            if (( ${#unique_games[@]} > 0 )); then
                for existing in "${unique_games[@]}"; do
                    if [[ "$existing" == "$game" ]]; then
                        already_seen=true
                        break
                    fi
                done
            fi
            if ! $already_seen; then
                unique_games+=("$game")
            fi
        done
    fi

    if (( ${#unique_games[@]} > 0 )); then
        printf '%s\0' "${unique_games[@]}"
    fi
}

worms_first_detected_game_app() {
    local game

    while IFS= read -r -d '' game; do
        printf '%s\n' "$game"
        return 0
    done < <(worms_find_game_apps)

    return 1
}

worms_dataosx_config_files() {
    printf '%s\n' \
        SteamConfig.txt \
        SteamConfigDemo.txt \
        GOGConfig.txt \
        PcLanConfig.txt \
        SwitchConfig.txt \
        SwitchConfigGOG.txt
}

worms_commondata_config_files() {
    printf '%s\n' \
        AnalyticsConfig.txt \
        HttpConfig.txt
}

worms_latest_path_by_mtime() {
    local search_dir="$1"
    local name_glob="$2"
    local type="${3:-d}"
    local result

    result=$(find "$search_dir" -mindepth 1 -maxdepth 1 -type "$type" -name "$name_glob" -print0 2>/dev/null \
        | while IFS= read -r -d '' item; do
            mtime=$(stat -f "%m" "$item" 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$mtime" "$item"
        done \
        | sort -nr \
        | head -1 \
        | cut -f2- || true)

    if [[ -n "$result" ]]; then
        echo "$result"
    fi
}

worms_version_ge() {
    local v1="$1"
    local v2="$2"
    local v1_parts v2_parts max_parts i p1 p2

    IFS='.' read -ra v1_parts <<< "$v1"
    IFS='.' read -ra v2_parts <<< "$v2"

    max_parts=${#v1_parts[@]}
    if [[ ${#v2_parts[@]} -gt $max_parts ]]; then
        max_parts=${#v2_parts[@]}
    fi

    for ((i = 0; i < max_parts; i++)); do
        p1="${v1_parts[$i]:-0}"
        p2="${v2_parts[$i]:-0}"

        [[ "$p1" =~ ^[0-9]+$ ]] || p1=0
        [[ "$p2" =~ ^[0-9]+$ ]] || p2=0

        if [[ "$p1" -gt "$p2" ]]; then
            return 0
        fi
        if [[ "$p1" -lt "$p2" ]]; then
            return 1
        fi
    done

    return 0
}

worms_supported_qt5_version() {
    local version="${1:-}"

    [[ "$version" =~ ^5[.]15[.][0-9]+$ ]]
}

worms_qt_package_version() {
    local package="$1"
    local name version

    name=$(basename "$package")
    case "$name" in
        qt-frameworks-x86_64-*.tar.gz)
            version=${name#qt-frameworks-x86_64-}
            version=${version%.tar.gz}
            ;;
        *)
            return 1
            ;;
    esac

    if worms_supported_qt5_version "$version"; then
        echo "$version"
        return 0
    fi

    return 1
}

worms_latest_qt_package_by_version() {
    local search_dir="$1"
    local require_checksum="${2:-false}"
    local package version best_version="" best_path=""

    [[ -d "$search_dir" ]] || return 1

    while IFS= read -r -d '' package; do
        version=$(worms_qt_package_version "$package" || true)
        [[ -n "$version" ]] || continue

        if [[ "$require_checksum" == "true" ]] && [[ ! -f "${package}.sha256" ]]; then
            continue
        fi

        if [[ -z "$best_version" ]] || worms_version_ge "$version" "$best_version"; then
            best_version="$version"
            best_path="$package"
        fi
    done < <(find "$search_dir" -mindepth 1 -maxdepth 1 -type f -name "qt-frameworks-x86_64-*.tar.gz" -print0 2>/dev/null)

    [[ -n "$best_path" ]] || return 1
    echo "$best_path"
}

worms_unique_path() {
    local base="$1"
    local suffix="${2:-}"
    local candidate
    local counter=1

    candidate="${base}${suffix}"
    while [[ -e "$candidate" ]]; do
        candidate="${base}-${counter}${suffix}"
        counter=$((counter + 1))
    done

    printf '%s\n' "$candidate"
}

worms_file_size() {
    local path="$1"

    stat -f "%z" "$path" 2>/dev/null || stat -c "%s" "$path" 2>/dev/null
}

worms_file_sha256() {
    local path="$1"

    shasum -a 256 "$path" | awk '{print $1}'
}

worms_text_sha256() {
    local value="$1"

    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
}

worms_text_size() {
    local value="$1"

    printf '%s' "$value" | LC_ALL=C wc -c | tr -d ' '
}

worms_manifest_hashes() {
    local root_dir="$1"
    local paths_file="$2"

    [[ -s "$paths_file" ]] || return 0

    (
        cd "$root_dir" || exit 1
        while IFS= read -r rel_path; do
            [[ -n "$rel_path" ]] || continue
            printf '%s\0' "$rel_path"
        done < "$paths_file" | xargs -0 shasum -a 256 --
    )
}

worms_otool_dependencies_from_stdin() {
    sed -n '
        /^[[:space:]]/ {
            s/^[[:space:]]*//
            s/[[:space:]]*(compatibility version .*$//
            /^$/d
            p
        }
    '
}

worms_otool_dependencies() {
    local bin="$1"

    otool -L "$bin" 2>/dev/null | worms_otool_dependencies_from_stdin || true
}

worms_macho_rpaths() {
    local bin="$1"

    otool -l "$bin" 2>/dev/null | awk '
        $1 == "cmd" {
            in_rpath = ($2 == "LC_RPATH")
            next
        }
        in_rpath && $1 == "path" {
            line = $0
            sub(/^[[:space:]]*path[[:space:]]+/, "", line)
            sub(/[[:space:]]+\(offset[[:space:]]+[0-9]+\)$/, "", line)
            print line
            in_rpath = 0
        }
    '
}

worms_macho_dependency_is_weak() {
    local bin="$1"
    local dependency="$2"

    otool -l "$bin" 2>/dev/null | awk -v dependency="$dependency" '
        $1 == "cmd" {
            load_command = $2
            next
        }
        $1 == "name" {
            line = $0
            sub(/^[[:space:]]*name[[:space:]]+/, "", line)
            sub(/[[:space:]]+\(offset[[:space:]]+[0-9]+\)$/, "", line)
            if (line == dependency && load_command == "LC_LOAD_WEAK_DYLIB") {
                found = 1
            }
            load_command = ""
        }
        END { exit(found ? 0 : 1) }
    '
}

worms_expand_macho_path() {
    local path="$1"
    local loader_bin="$2"
    local game_exec="$3"

    case "$path" in
        @executable_path)
            printf '%s\n' "$(dirname "$game_exec")"
            ;;
        @executable_path/*)
            printf '%s%s\n' "$(dirname "$game_exec")" "${path#@executable_path}"
            ;;
        @loader_path)
            printf '%s\n' "$(dirname "$loader_bin")"
            ;;
        @loader_path/*)
            printf '%s%s\n' "$(dirname "$loader_bin")" "${path#@loader_path}"
            ;;
        /*)
            printf '%s\n' "$path"
            ;;
        *)
            return 1
            ;;
    esac
}

worms_resolve_macho_rpath_dependency() {
    local bin="$1"
    local dependency="$2"
    local game_exec="$3"
    local game_app="$4"
    local dependency_suffix
    local rpath expanded candidate candidate_real rpath_bin

    [[ "$dependency" == @rpath/* ]] || return 1
    dependency_suffix=${dependency#@rpath/}

    for rpath_bin in "$bin" "$game_exec"; do
        [[ -f "$rpath_bin" ]] || continue
        while IFS= read -r rpath; do
            [[ -n "$rpath" ]] || continue
            expanded=$(worms_expand_macho_path "$rpath" "$rpath_bin" "$game_exec" || true)
            [[ -n "$expanded" ]] || continue
            candidate="${expanded%/}/$dependency_suffix"
            [[ -f "$candidate" ]] || continue
            if [[ -L "$candidate" ]]; then
                command -v realpath >/dev/null 2>&1 || continue
                candidate_real=$(realpath "$candidate" 2>/dev/null || true)
                [[ -n "$candidate_real" ]] || continue
            else
                candidate_real="$candidate"
            fi
            if worms_path_inside_root "$game_app/Contents" "$candidate_real"; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done < <(worms_macho_rpaths "$rpath_bin")
        [[ "$rpath_bin" == "$game_exec" ]] && break
    done

    return 1
}

worms_file_link_count() {
    local path="$1"

    stat -f "%l" "$path" 2>/dev/null || stat -c "%h" "$path" 2>/dev/null || echo 1
}

worms_has_control_chars() {
    local value="$1"

    case "$value" in
        *$'\n'*|*$'\r'*|*$'\t'*)
            return 0
            ;;
    esac

    return 1
}

worms_reject_control_chars() {
    local value="$1"
    local label="$2"

    if worms_has_control_chars "$value"; then
        echo "Unsafe control character in $label" >&2
        return 1
    fi
}

worms_path_has_parent_escape() {
    local path="$1"

    case "$path" in
        /*|..|../*|*/..|*/../*)
            return 0
            ;;
    esac

    return 1
}

worms_real_dir() {
    local path="$1"

    (cd "$path" 2>/dev/null && pwd -P)
}

worms_path_inside_root() {
    local root="$1"
    local path="$2"
    local root_real
    local path_real

    root_real=$(worms_real_dir "$root") || return 1
    if [[ -d "$path" ]]; then
        path_real=$(worms_real_dir "$path") || return 1
    else
        path_real=$(worms_real_dir "$(dirname "$path")") || return 1
        path_real="$path_real/$(basename "$path")"
    fi

    case "$path_real" in
        "$root_real"|"$root_real"/*)
            return 0
            ;;
    esac

    return 1
}

worms_path_creatable_inside_root() {
    local root="$1"
    local path="$2"
    local root_real probe component probe_real

    case "$path" in
        /*)
            ;;
        *)
            return 1
            ;;
    esac
    case "$path" in
        ..|../*|*/..|*/../*)
            return 1
            ;;
    esac

    root_real=$(worms_real_dir "$root") || return 1
    if [[ -e "$path" ]] && [[ ! -d "$path" ]]; then
        probe=$(dirname "$path")
    else
        probe="$path"
    fi

    while [[ ! -e "$probe" ]]; do
        component=$(basename "$probe")
        case "$component" in
            ""|"."|"..")
                return 1
                ;;
        esac
        probe=$(dirname "$probe")
    done

    [[ -d "$probe" ]] || return 1
    probe_real=$(worms_real_dir "$probe") || return 1
    case "$probe_real" in
        "$root_real"|"$root_real"/*)
            return 0
            ;;
    esac

    return 1
}

worms_validate_tree_symlinks() {
    local root_dir="$1"
    local root_real
    local link_path link_dir target target_dir target_base target_real status=0

    root_real=$(worms_real_dir "$root_dir") || return 1

    while IFS= read -r -d '' link_path; do
        target=$(readlink "$link_path" 2>/dev/null || true)
        if [[ -z "$target" ]] || worms_path_has_parent_escape "$target"; then
            echo "Unsafe symlink target: $link_path -> ${target:-}" >&2
            status=1
            continue
        fi

        link_dir=$(dirname "$link_path")
        target_dir=$(dirname "$target")
        target_base=$(basename "$target")
        target_real=$(cd "$link_dir/$target_dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$target_base" || true)
        case "$target_real" in
            "$root_real"|"$root_real"/*)
                ;;
            *)
                echo "Symlink escapes root: $link_path -> $target" >&2
                status=1
                ;;
        esac
    done < <(find "$root_dir" -type l -print0 2>/dev/null)

    return "$status"
}

worms_repair_agl_framework_symlinks() {
    local root_dir="$1"
    local agl_framework="$root_dir/Frameworks/AGL.framework"
    local link_path

    [[ -d "$agl_framework" ]] || return 0
    [[ -f "$agl_framework/Versions/A/AGL" ]] || return 0

    for link_path in \
        "$agl_framework/AGL" \
        "$agl_framework/Resources" \
        "$agl_framework/Versions/Current" \
        "$agl_framework/Versions/A/A" \
        "$agl_framework/Versions/A/Resources/Resources"; do
        if [[ -L "$link_path" ]]; then
            rm -f "$link_path"
        fi
    done

    mkdir -p "$agl_framework/Versions/A/Resources"
    [[ -e "$agl_framework/Versions/Current" ]] || ln -s A "$agl_framework/Versions/Current"
    [[ -e "$agl_framework/AGL" ]] || ln -s Versions/Current/AGL "$agl_framework/AGL"
    [[ -e "$agl_framework/Resources" ]] || ln -s Versions/Current/Resources "$agl_framework/Resources"
}

worms_validate_game_app_for_mutation() {
    local game_app="$1"
    local root_real contents contents_real path path_real
    local critical_paths

    if [[ -z "$game_app" ]] || [[ ! -d "$game_app" ]] || [[ ! -d "$game_app/Contents" ]]; then
        echo "Invalid game app path: $game_app" >&2
        return 1
    fi

    root_real=$(worms_real_dir "$game_app") || return 1
    contents="$game_app/Contents"
    if [[ -L "$contents" ]]; then
        echo "Refusing symlinked game bundle Contents path: $contents" >&2
        return 1
    fi
    contents_real=$(worms_real_dir "$contents") || return 1
    if [[ "$contents_real" != "$root_real/Contents" ]]; then
        echo "Game bundle Contents resolves outside the app: $contents" >&2
        return 1
    fi

    critical_paths=(
        "$contents/MacOS"
        "$contents/Frameworks"
        "$contents/PlugIns"
        "$contents/PlugIns/platforms"
        "$contents/PlugIns/imageformats"
        "$contents/Resources"
        "$contents/Resources/DataOSX"
        "$contents/Resources/CommonData"
    )

    for path in "${critical_paths[@]}"; do
        [[ -e "$path" ]] || continue
        if [[ -L "$path" ]]; then
            echo "Refusing symlinked game bundle mutation path: $path" >&2
            return 1
        fi
        if [[ ! -d "$path" ]]; then
            echo "Refusing non-directory game bundle mutation path: $path" >&2
            return 1
        fi
        path_real=$(worms_real_dir "$path") || return 1
        case "$path_real" in
            "$contents_real"|"$contents_real"/*)
                ;;
            *)
                echo "Game bundle mutation path resolves outside Contents: $path" >&2
                return 1
                ;;
        esac
    done

    return 0
}

worms_refuse_linked_file_for_mutation() {
    local path="$1"
    local label="${2:-file}"
    local link_count

    if [[ -L "$path" ]]; then
        echo "Refusing symlinked $label: $path" >&2
        return 1
    fi
    if [[ -e "$path" ]] && [[ ! -f "$path" ]]; then
        echo "Refusing non-regular $label: $path" >&2
        return 1
    fi

    link_count=$(worms_file_link_count "$path")
    if [[ "$link_count" =~ ^[0-9]+$ ]] && [[ "$link_count" -gt 1 ]]; then
        echo "Refusing hardlinked $label: $path" >&2
        return 1
    fi
}

worms_validate_no_special_entries() {
    local root_dir="$1"
    local bad_entry

    bad_entry=$(find "$root_dir" ! -type f ! -type d -print -quit 2>/dev/null || true)
    if [[ -n "$bad_entry" ]]; then
        echo "Refusing non-regular archive entry after extraction: $bad_entry" >&2
        return 1
    fi
}

worms_validate_tar_entry_metadata() {
    local archive="$1"
    local symlink_policy="${2:-reject-symlinks}"
    local listing line entry_type target

    if ! listing=$(tar -tzvf "$archive" 2>/dev/null); then
        echo "Unable to read archive metadata: $archive" >&2
        return 1
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        entry_type="${line:0:1}"

        case "$entry_type" in
            -|d)
                ;;
            l)
                if [[ "$symlink_policy" != "allow-relative-symlinks" ]]; then
                    echo "Archive contains a symbolic link entry: $line" >&2
                    return 1
                fi
                if [[ "$line" != *" -> "* ]]; then
                    echo "Archive symbolic link is missing a target: $line" >&2
                    return 1
                fi
                target="${line##* -> }"
                if [[ -z "$target" ]] || worms_path_has_parent_escape "$target"; then
                    echo "Archive contains an unsafe symbolic link target: $line" >&2
                    return 1
                fi
                ;;
            *)
                echo "Archive contains unsupported entry type: $line" >&2
                return 1
                ;;
        esac
    done <<< "$listing"
}

worms_validate_tar_no_duplicate_entries() {
    local archive="$1"
    local duplicate listing

    if ! listing=$(tar -tzf "$archive" 2>/dev/null); then
        echo "Unable to read archive entries: $archive" >&2
        return 1
    fi

    duplicate=$(printf '%s\n' "$listing" | awk '
        {
            entry = $0
            sub(/^\.\//, "", entry)
            while (sub(/\/$/, "", entry)) { }
            if (entry == "") next
            if (seen[entry]++) {
                print entry
                exit
            }
        }
    ')
    if [[ -n "$duplicate" ]]; then
        echo "Archive contains duplicate entry: $duplicate" >&2
        return 1
    fi
}

worms_write_manifest() {
    local root_dir="$1"
    local manifest_file="$2"
    local entries_file files_file data_file hash hash_line rel_path entry_type extra status=0
    local target target_hash target_size
    shift 2

    entries_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-entries.XXXXXX")
    files_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-files.XXXXXX")
    data_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-data.XXXXXX")

    (
        cd "$root_dir" || exit 1
        for rel in "$@"; do
            [[ -e "$rel" ]] || continue
            if [[ -L "$rel" ]]; then
                printf '%s\n' "$rel"
            elif [[ -d "$rel" ]]; then
                find "$rel" \( -type f -o -type l \) -print
            elif [[ -f "$rel" ]]; then
                printf '%s\n' "$rel"
            fi
        done | LC_ALL=C sort | while IFS= read -r rel_path; do
            [[ -n "$rel_path" ]] || continue
            if [[ "$rel_path" == *$'\t'* ]]; then
                echo "Skipping manifest path with tab: $rel_path" >&2
                continue
            fi
            if [[ -L "$rel_path" ]]; then
                printf 'symlink\t%s\n' "$rel_path"
            else
                printf 'file\t%s\n' "$rel_path"
            fi
        done
    ) > "$entries_file"

    awk -F '\t' '$1 == "file" {sub(/^[^\t]*\t/, ""); print}' "$entries_file" > "$files_file"

    worms_manifest_hashes "$root_dir" "$files_file" | while IFS= read -r hash_line; do
        [[ -n "$hash_line" ]] || continue
        hash=${hash_line%% *}
        rel_path=${hash_line#*  }
        printf '%s\t%s\t%s\n' "$hash" "$(worms_file_size "$root_dir/$rel_path")" "$rel_path"
    done > "$data_file"

    while IFS=$'\t' read -r entry_type rel_path extra; do
        [[ "$entry_type" == "symlink" ]] || continue
        if [[ -n "${extra:-}" ]] || [[ -z "$rel_path" ]]; then
            echo "Invalid symlink manifest path: $rel_path" >&2
            status=1
            break
        fi
        target=$(readlink "$root_dir/$rel_path" 2>/dev/null || true)
        if [[ -z "$target" ]] || worms_has_control_chars "$target"; then
            echo "Unsafe symlink target in manifest input: $rel_path" >&2
            status=1
            break
        fi
        target_hash=$(worms_text_sha256 "$target")
        target_size=$(worms_text_size "$target")
        printf 'symlink:%s\t%s\t%s\n' "$target_hash" "$target_size" "$rel_path" >> "$data_file"
    done < "$entries_file"

    if [[ "$status" -ne 0 ]]; then
        rm -f "$entries_file" "$files_file" "$data_file"
        return 1
    fi

    {
        echo "# WormsWMD manifest v2"
        echo "# sha256-or-symlink-digest	size	path"
        LC_ALL=C sort -t $'\t' -k3,3 "$data_file"
    } > "$manifest_file"

    rm -f "$entries_file" "$files_file" "$data_file"
}

worms_verify_manifest() {
    local root_dir="$1"
    local manifest_file="$2"
    local expected_hash expected_size rel_path actual_size status=0
    local paths_file expected_file actual_file tree_file tree_expected_file
    local hash_line actual_hash actual_path actual_extra
    local root_real manifest_dir_real manifest_rel="" extra_path manifest_version
    local symlink_hash symlink_target

    [[ -f "$manifest_file" ]] || return 1

    paths_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-paths.XXXXXX")
    expected_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-expected.XXXXXX")
    actual_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-actual.XXXXXX")
    tree_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-tree.XXXXXX")
    tree_expected_file=$(mktemp "${TMPDIR:-/tmp}/wormswmd-manifest-tree-expected.XXXXXX")

    manifest_version=$(sed -n 's/^# WormsWMD manifest v\([0-9][0-9]*\)$/\1/p' "$manifest_file" | head -1)
    manifest_version=${manifest_version:-1}
    if [[ "$manifest_version" != "1" ]] && [[ "$manifest_version" != "2" ]]; then
        echo "Unsupported manifest version: $manifest_version" >&2
        rm -f "$paths_file" "$expected_file" "$actual_file" "$tree_file" "$tree_expected_file"
        return 1
    fi

    while IFS=$'\t' read -r expected_hash expected_size rel_path extra; do
        [[ -n "${expected_hash:-}" ]] || continue
        [[ "$expected_hash" == \#* ]] && continue

        if [[ -n "${extra:-}" ]] || [[ -z "${rel_path:-}" ]]; then
            echo "Invalid manifest line in $manifest_file" >&2
            status=1
            continue
        fi
        if worms_path_has_parent_escape "$rel_path"; then
            echo "Unsafe manifest path: $rel_path" >&2
            status=1
            continue
        fi
        printf '%s\n' "$rel_path" >> "$tree_expected_file"

        if [[ "$expected_hash" == symlink:* ]]; then
            symlink_hash=${expected_hash#symlink:}
            if [[ "$manifest_version" != "2" ]] \
                || [[ ! "$symlink_hash" =~ ^[a-fA-F0-9]{64}$ ]] \
                || [[ ! "$expected_size" =~ ^[0-9]+$ ]]; then
                echo "Invalid manifest symlink checksum or size for $rel_path" >&2
                status=1
                continue
            fi
            if [[ ! -L "$root_dir/$rel_path" ]]; then
                echo "Manifest symlink missing: $rel_path" >&2
                status=1
                continue
            fi
            symlink_target=$(readlink "$root_dir/$rel_path" 2>/dev/null || true)
            actual_size=$(worms_text_size "$symlink_target")
            actual_hash=$(worms_text_sha256 "$symlink_target")
            if [[ "$actual_size" != "$expected_size" ]] || [[ "$actual_hash" != "$symlink_hash" ]]; then
                echo "Manifest symlink mismatch: $rel_path" >&2
                status=1
            fi
            continue
        fi

        if [[ ! "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]] || [[ ! "$expected_size" =~ ^[0-9]+$ ]]; then
            echo "Invalid manifest checksum or size for $rel_path" >&2
            status=1
            continue
        fi
        if [[ ! -f "$root_dir/$rel_path" ]] || [[ -L "$root_dir/$rel_path" ]]; then
            echo "Manifest file missing: $rel_path" >&2
            status=1
            continue
        fi

        actual_size=$(worms_file_size "$root_dir/$rel_path")
        if [[ "$actual_size" != "$expected_size" ]]; then
            echo "Manifest mismatch: $rel_path" >&2
            status=1
            continue
        fi

        printf '%s\n' "$rel_path" >> "$paths_file"
        printf '%s\t%s\n' "$expected_hash" "$rel_path" >> "$expected_file"
    done < "$manifest_file"

    root_real=$(worms_real_dir "$root_dir") || status=1
    manifest_dir_real=$(worms_real_dir "$(dirname "$manifest_file")" || true)
    if [[ -n "$root_real" ]] && [[ "$manifest_dir_real" == "$root_real" ]]; then
        manifest_rel=$(basename "$manifest_file")
    elif [[ -n "$root_real" ]] && [[ "$manifest_dir_real" == "$root_real"/* ]]; then
        manifest_rel="${manifest_dir_real#"$root_real"/}/$(basename "$manifest_file")"
    fi

    (
        cd "$root_dir" || exit 1
        if [[ "$manifest_version" == "2" ]]; then
            find . \( -type f -o -type l \) -print
        else
            find . -type f -print
        fi | sed 's#^\./##'
    ) | while IFS= read -r actual_path; do
        [[ -n "$actual_path" ]] || continue
        [[ "$actual_path" == "$manifest_rel" ]] && continue
        printf '%s\n' "$actual_path"
    done > "$tree_file"
    extra_path=$(awk 'NR == FNR {expected[$0]=1; next} !($0 in expected) {print; exit}' "$tree_expected_file" "$tree_file")
    if [[ -n "$extra_path" ]]; then
        echo "Manifest contains unrecorded file: $extra_path" >&2
        status=1
    fi

    worms_manifest_hashes "$root_dir" "$paths_file" | while IFS= read -r hash_line; do
        [[ -n "$hash_line" ]] || continue
        actual_hash=${hash_line%% *}
        actual_path=${hash_line#*  }
        printf '%s\t%s\n' "$actual_hash" "$actual_path"
    done > "$actual_file"

    exec 3< "$actual_file"
    while IFS=$'\t' read -r expected_hash rel_path; do
        if ! IFS=$'\t' read -r actual_hash actual_path actual_extra <&3; then
            echo "Manifest hash missing: $rel_path" >&2
            status=1
            continue
        fi
        if [[ -n "${actual_extra:-}" ]] || [[ "$actual_path" != "$rel_path" ]] || [[ "$actual_hash" != "$expected_hash" ]]; then
            echo "Manifest mismatch: $rel_path" >&2
            status=1
        fi
    done < "$expected_file"

    if IFS=$'\t' read -r actual_hash actual_path actual_extra <&3; then
        echo "Manifest contains unexpected hash output: $actual_path" >&2
        status=1
    fi
    exec 3<&-

    rm -f "$paths_file" "$expected_file" "$actual_file" "$tree_file" "$tree_expected_file"

    return "$status"
}

worms_framework_binary() {
    local fw_dir="$1"
    local fw_name="${2:-}"
    local candidate

    if [[ -z "$fw_name" ]]; then
        fw_name=$(basename "$fw_dir" .framework)
    fi

    for candidate in \
        "$fw_dir/Versions/5/$fw_name" \
        "$fw_dir/Versions/Current/$fw_name" \
        "$fw_dir/Versions/A/$fw_name" \
        "$fw_dir/$fw_name"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}
