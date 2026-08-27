#!/bin/bash
# Compile a direct QImageReader probe and read a deterministic 1x1 TIFF.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

fail() {
    printf 'Qt TIFF runtime check failed: %s\n' "$*" >&2
    exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-qt-tiff.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
runtime_root="$tmp_dir/runtime"
mkdir -p "$runtime_root"

archive="$ROOT_DIR/dist/qt-frameworks-x86_64-5.15.19.tar.gz"
archive_sha=$(awk 'NR == 1 {print $1; exit}' "${archive}.sha256")
worms_copy_and_inspect_archive \
    "$archive" "$tmp_dir/inspected.tar.gz" qt "$archive_sha" --quiet
tar -xzf "$tmp_dir/inspected.tar.gz" -C "$runtime_root"
"$ROOT_DIR/tools/normalize_qt_macho_tree.sh" "$runtime_root"

headers_prefix="${QT_HEADERS_PREFIX:-}"
if [[ -z "$headers_prefix" ]]; then
    headers_prefix="$tmp_dir/headers-prefix"
    ruby - "$ROOT_DIR/tools/fetch_qt_homebrew_bottles.rb" \
        "$ROOT_DIR/packaging/qt-homebrew-lock.tsv" \
        "$headers_prefix" "$tmp_dir/bottle-cache" <<'RUBY'
require ARGV.shift
lock, output, cache_path = ARGV
entries = WormsBottleFetcher.read_lock(lock)
qt = entries.find { |entry| entry.fetch('name') == 'qt@5' }
raise WormsBottleFetcher::Error, 'Lock omitted qt@5' unless qt
target = WormsBottleFetcher.validate_output_target(output)
cache = WormsBottleFetcher.safe_cache_directory(cache_path)
WormsBottleFetcher.build_prefix!([qt], target, cache)
RUBY
fi
qt_headers="$headers_prefix/opt/qt@5"
[[ -f "$qt_headers/lib/QtGui.framework/Headers/QImageReader" ]] \
    || fail "QtGui headers are unavailable at: $qt_headers"

/usr/bin/python3 - "$tmp_dir/pixel.tiff" <<'PY'
import struct
import sys

output = sys.argv[1]
entries = []
ifd_offset = 8
entry_count = 10
ifd_size = 2 + entry_count * 12 + 4
bits_offset = ifd_offset + ifd_size
pixel_offset = bits_offset + 6

def short(tag, value):
    entries.append(struct.pack('<HHI4s', tag, 3, 1, struct.pack('<H', value) + b'\0\0'))

def long(tag, value):
    entries.append(struct.pack('<HHII', tag, 4, 1, value))

short(256, 1)
short(257, 1)
entries.append(struct.pack('<HHII', 258, 3, 3, bits_offset))
short(259, 1)
short(262, 2)
long(273, pixel_offset)
short(277, 3)
long(278, 1)
long(279, 3)
short(284, 1)
with open(output, 'wb') as handle:
    handle.write(b'II' + struct.pack('<HI', 42, ifd_offset))
    handle.write(struct.pack('<H', entry_count))
    handle.write(b''.join(entries))
    handle.write(struct.pack('<I', 0))
    handle.write(struct.pack('<HHH', 8, 8, 8))
    handle.write(bytes([255, 0, 0]))
PY

cat > "$tmp_dir/tiff_probe.cpp" <<'CPP'
#include <QtCore/QCoreApplication>
#include <QtCore/QString>
#include <QtGui/QImage>
#include <QtGui/QImageReader>

int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    if (argc != 2) return 10;
    QImageReader reader(QString::fromUtf8(argv[1]), "tiff");
    if (!reader.canRead()) return 11;
    const QImage image = reader.read();
    if (image.isNull()) return 12;
    if (image.width() != 1 || image.height() != 1) return 13;
    const QRgb pixel = image.pixel(0, 0);
    if (qRed(pixel) < 250 || qGreen(pixel) > 5 || qBlue(pixel) > 5) return 14;
    return 0;
}
CPP

/usr/bin/clang++ -std=c++17 -arch x86_64 \
    -F "$qt_headers/lib" \
    -c "$tmp_dir/tiff_probe.cpp" -o "$tmp_dir/tiff_probe.o"
/usr/bin/clang++ -arch x86_64 "$tmp_dir/tiff_probe.o" \
    -F "$runtime_root/Frameworks" \
    -framework QtCore -framework QtGui \
    -Wl,-rpath,"$runtime_root/Frameworks" \
    -o "$tmp_dir/tiff_probe"

QT_PLUGIN_PATH="$runtime_root/PlugIns" \
    /usr/bin/arch -x86_64 "$tmp_dir/tiff_probe" "$tmp_dir/pixel.tiff" \
    || fail "QImageReader could not decode the synthetic TIFF"

printf 'Qt TIFF runtime check passed.\n'
