#!/bin/bash
# Extract one released version section from CHANGELOG.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-}"

if [[ $# -ne 1 ]] || [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    printf 'Usage: %s VERSION\n' "$(basename "$0")" >&2
    exit 2
fi

awk -v target="## $VERSION (" '
    index($0, target) == 1 {
        found = 1
        capture = 1
    }
    capture && /^## / && index($0, target) != 1 {
        exit
    }
    capture {
        print
    }
    END {
        if (!found) {
            exit 1
        }
    }
' "$ROOT_DIR/CHANGELOG.md"
