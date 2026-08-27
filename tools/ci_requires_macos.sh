#!/bin/bash
# Return success when changed paths require the full macOS CI job.

set -euo pipefail

SAW_PATH=false

while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || continue
    SAW_PATH=true

    case "$path" in
        *.md|docs/*|.agents/*|assets/*)
            continue
            ;;
        .github/CODEOWNERS|.github/dependabot.yml)
            continue
            ;;
        .github/ISSUE_TEMPLATE/*|.github/workflows/github-security.yml)
            continue
            ;;
        .gitignore|LICENSE)
            continue
            ;;
        *)
            exit 0
            ;;
    esac
done

# Empty/invalid diffs fail safe and require macOS.
$SAW_PATH || exit 0
exit 1
