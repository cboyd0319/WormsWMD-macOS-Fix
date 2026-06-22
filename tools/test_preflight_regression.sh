#!/bin/bash
#
# Regression checks for preflight diagnostic edge cases.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
preflight="$ROOT_DIR/tools/preflight_check.sh"

fail() {
    printf 'preflight regression check failed: %s\n' "$*" >&2
    exit 1
}

if grep -Fq 'https://ads.t17service.com' "$preflight"; then
    fail "preflight still uses the noisy Team17 service root URL"
fi

grep -Fq "team17_status=\$(http_status \"https://www.team17.com/games/worms-w-m-d\")" "$preflight" \
    || fail "Team17 network check does not use the public Worms W.M.D page"
grep -Fq "steam_status=\$(http_status \"https://store.steampowered.com/app/327030/Worms_WMD/\")" "$preflight" \
    || fail "Steam network check does not use the Worms W.M.D store page"
grep -Fq "gog_status=\$(http_status \"https://www.gog.com/en/game/worms_wmd\")" "$preflight" \
    || fail "GOG network check does not use the Worms W.M.D store page"
grep -Fq 'Team17 Worms W.M.D page reachable' "$preflight" \
    || fail "Team17 network check has the wrong user-facing label"
grep -Fq 'Steam Worms W.M.D store page reachable' "$preflight" \
    || fail "Steam network check has the wrong user-facing label"
grep -Fq 'GOG Worms W.M.D store page reachable' "$preflight" \
    || fail "GOG network check has the wrong user-facing label"
grep -Fq 'current version \([0-9][0-9.]*\)' "$preflight" \
    || fail "preflight does not parse the QtCore current version"
grep -Fq 'binary_archs()' "$preflight" \
    || fail "preflight architecture helper is missing"

printf 'Preflight regression check passed.\n'
