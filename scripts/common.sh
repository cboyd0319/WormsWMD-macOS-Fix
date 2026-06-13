#!/bin/bash
#
# common.sh - shared helpers for Worms W.M.D fix scripts and tools
#

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

    if [[ "$version" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
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

worms_file_size() {
    local path="$1"

    stat -f "%z" "$path" 2>/dev/null || stat -c "%s" "$path" 2>/dev/null
}

worms_file_sha256() {
    local path="$1"

    shasum -a 256 "$path" | awk '{print $1}'
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

worms_file_link_count() {
    local path="$1"

    stat -f "%l" "$path" 2>/dev/null || stat -c "%h" "$path" 2>/dev/null || echo 1
}

worms_has_control_chars() {
    local value="$1"

    case "$value" in
        *$'\n'*|*$'\r'*)
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
        if [[ -d "$path" ]]; then
            path_real=$(worms_real_dir "$path") || return 1
            case "$path_real" in
                "$contents_real"|"$contents_real"/*)
                    ;;
                *)
                    echo "Game bundle mutation path resolves outside Contents: $path" >&2
                    return 1
                    ;;
            esac
        fi
    done
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

worms_write_manifest() {
    local root_dir="$1"
    local manifest_file="$2"
    shift 2

    {
        echo "# WormsWMD manifest v1"
        echo "# sha256	size	path"
        (
            cd "$root_dir" || exit 1
            for rel in "$@"; do
                [[ -e "$rel" ]] || continue
                if [[ -d "$rel" ]]; then
                    find "$rel" -type f -print
                elif [[ -f "$rel" ]]; then
                    printf '%s\n' "$rel"
                fi
            done | LC_ALL=C sort | while IFS= read -r rel_path; do
                [[ -n "$rel_path" ]] || continue
                if [[ "$rel_path" == *$'\t'* ]]; then
                    echo "Skipping manifest path with tab: $rel_path" >&2
                    continue
                fi
                printf '%s\t%s\t%s\n' "$(worms_file_sha256 "$rel_path")" "$(worms_file_size "$rel_path")" "$rel_path"
            done
        )
    } > "$manifest_file"
}

worms_verify_manifest() {
    local root_dir="$1"
    local manifest_file="$2"
    local expected_hash expected_size rel_path actual_hash actual_size status=0

    [[ -f "$manifest_file" ]] || return 1

    while IFS=$'\t' read -r expected_hash expected_size rel_path extra; do
        [[ -n "${expected_hash:-}" ]] || continue
        [[ "$expected_hash" == \#* ]] && continue

        if [[ -n "${extra:-}" ]] || [[ -z "${rel_path:-}" ]]; then
            echo "Invalid manifest line in $manifest_file" >&2
            status=1
            continue
        fi
        if [[ ! "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]] || [[ ! "$expected_size" =~ ^[0-9]+$ ]]; then
            echo "Invalid manifest checksum or size for $rel_path" >&2
            status=1
            continue
        fi
        if worms_path_has_parent_escape "$rel_path"; then
            echo "Unsafe manifest path: $rel_path" >&2
            status=1
            continue
        fi
        if [[ ! -f "$root_dir/$rel_path" ]]; then
            echo "Manifest file missing: $rel_path" >&2
            status=1
            continue
        fi

        actual_hash=$(worms_file_sha256 "$root_dir/$rel_path")
        actual_size=$(worms_file_size "$root_dir/$rel_path")
        if [[ "$actual_hash" != "$expected_hash" ]] || [[ "$actual_size" != "$expected_size" ]]; then
            echo "Manifest mismatch: $rel_path" >&2
            status=1
        fi
    done < "$manifest_file"

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
