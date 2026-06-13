#!/bin/bash
#
# Regression check for Mach-O dependency parsing.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

actual=$(
    cat <<'EOF' | worms_otool_dependencies_from_stdin
/Games/Worms W.M.D.app/Contents/Frameworks/libexample.dylib (architecture x86_64):
	/Users/example/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/libfmodex.dylib (compatibility version 1.0.0, current version 1.0.0)
	@rpath/libsharpyuv.0.dylib (compatibility version 2.0.0, current version 2.2.0)
	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
/Games/Worms W.M.D.app/Contents/Frameworks/libexample.dylib (architecture arm64):
	/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL (compatibility version 1.0.0, current version 1.0.0)
EOF
)

expected=$'/Users/example/Library/Application Support/Steam/steamapps/common/WormsWMD/Worms W.M.D.app/Contents/Frameworks/libfmodex.dylib\n@rpath/libsharpyuv.0.dylib\n/usr/lib/libSystem.B.dylib\n/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL'

if [[ "$actual" != "$expected" ]]; then
    printf 'dependency parsing failed\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
fi

printf 'Dependency parsing regression check passed.\n'
