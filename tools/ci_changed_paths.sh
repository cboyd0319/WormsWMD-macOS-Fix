#!/bin/bash
# Emit a NUL-delimited changed-path list using event-correct Git semantics.

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    printf '%s\n' "USAGE: ci_changed_paths.sh pull_request|push BASE_SHA HEAD_SHA" >&2
    exit 2
fi

event_name="$1"
base_sha="$2"
head_sha="$3"

if [[ ! "$base_sha" =~ ^[0-9a-f]{40}$ || ! "$head_sha" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "ERROR: BASE_SHA and HEAD_SHA must be full lowercase Git object IDs." >&2
    exit 1
fi
if ! git cat-file -e "$base_sha^{commit}" 2>/dev/null \
    || ! git cat-file -e "$head_sha^{commit}" 2>/dev/null; then
    printf '%s\n' "ERROR: BASE_SHA or HEAD_SHA is not an available commit." >&2
    exit 1
fi

case "$event_name" in
    pull_request)
        git diff --no-renames --name-only -z "$base_sha...$head_sha" --
        ;;
    push)
        git diff --no-renames --name-only -z "$base_sha" "$head_sha" --
        ;;
    *)
        printf 'ERROR: Unsupported GitHub event for path selection: %s\n' "$event_name" >&2
        exit 1
        ;;
esac
