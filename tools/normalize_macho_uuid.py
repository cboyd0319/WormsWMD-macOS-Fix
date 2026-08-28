#!/usr/bin/env python3
"""Recompute Mach-O LC_UUID values from UUID-neutral normalized bytes."""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import struct
import sys
import tempfile
from collections.abc import Sequence
from pathlib import Path

LC_UUID = 0x1B
MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_FAT_SLICES = 32
MAX_LOAD_COMMANDS = 16_384

THIN_MAGICS = {
    b"\xce\xfa\xed\xfe": ("<", 28),
    b"\xcf\xfa\xed\xfe": ("<", 32),
    b"\xfe\xed\xfa\xce": (">", 28),
    b"\xfe\xed\xfa\xcf": (">", 32),
}
FAT_MAGICS = {
    b"\xca\xfe\xba\xbe": (">", False),
    b"\xbe\xba\xfe\xca": ("<", False),
    b"\xca\xfe\xba\xbf": (">", True),
    b"\xbf\xba\xfe\xca": ("<", True),
}


class MachOError(ValueError):
    """Raised when Mach-O structure cannot be safely normalized."""


def require_range(start: int, size: int, limit: int, label: str) -> None:
    if start < 0 or size < 0 or start > limit or size > limit - start:
        raise MachOError(f"{label} exceeds its containing Mach-O range")


def macho_slices(data: bytes) -> list[tuple[int, int]]:
    if len(data) < 4:
        raise MachOError("Mach-O input is too short")
    magic = data[:4]
    if magic in THIN_MAGICS:
        return [(0, len(data))]
    fat = FAT_MAGICS.get(magic)
    if fat is None:
        raise MachOError("Input does not use a supported Mach-O magic")
    endian, is_64 = fat
    require_range(0, 8, len(data), "Fat Mach-O header")
    slice_count = struct.unpack_from(f"{endian}I", data, 4)[0]
    if slice_count == 0 or slice_count > MAX_FAT_SLICES:
        raise MachOError("Fat Mach-O has an invalid slice count")
    format_string = f"{endian}IIQQII" if is_64 else f"{endian}IIIII"
    entry_size = struct.calcsize(format_string)
    require_range(8, slice_count * entry_size, len(data), "Fat architecture table")
    slices: list[tuple[int, int]] = []
    for index in range(slice_count):
        fields = struct.unpack_from(format_string, data, 8 + index * entry_size)
        offset, size = fields[2], fields[3]
        require_range(offset, size, len(data), f"Fat slice {index}")
        slices.append((offset, size))
    ordered = sorted(slices)
    for previous, current in zip(ordered, ordered[1:]):
        if previous[0] + previous[1] > current[0]:
            raise MachOError("Fat Mach-O slices overlap")
    return slices


def uuid_offsets_for_slice(
    data: bytes, slice_offset: int, slice_size: int
) -> list[int]:
    require_range(slice_offset, 4, len(data), "Mach-O slice magic")
    thin = THIN_MAGICS.get(data[slice_offset:slice_offset + 4])
    if thin is None:
        raise MachOError("Fat slice does not contain a supported thin Mach-O")
    endian, header_size = thin
    slice_end = slice_offset + slice_size
    require_range(slice_offset, header_size, slice_end, "Mach-O header")
    command_count, command_bytes = struct.unpack_from(
        f"{endian}II", data, slice_offset + 16
    )
    if command_count > MAX_LOAD_COMMANDS:
        raise MachOError("Mach-O has too many load commands")
    commands_start = slice_offset + header_size
    require_range(commands_start, command_bytes, slice_end, "Mach-O load commands")
    commands_end = commands_start + command_bytes
    cursor = commands_start
    uuid_offsets: list[int] = []
    for _ in range(command_count):
        require_range(cursor, 8, commands_end, "Mach-O load command header")
        command, command_size = struct.unpack_from(f"{endian}II", data, cursor)
        if command_size < 8 or command_size % 4 != 0:
            raise MachOError("Mach-O load command has an invalid size")
        require_range(cursor, command_size, commands_end, "Mach-O load command")
        if command == LC_UUID:
            if command_size != 24 or uuid_offsets:
                raise MachOError("Mach-O must have at most one valid LC_UUID per slice")
            uuid_offsets.append(cursor + 8)
        cursor += command_size
    if cursor != commands_end:
        raise MachOError("Mach-O load command sizes do not match sizeofcmds")
    return uuid_offsets


def normalized_macho_bytes(data: bytes) -> bytes:
    slices = macho_slices(data)
    offsets: list[tuple[int, int, int]] = []
    for slice_offset, slice_size in slices:
        for uuid_offset in uuid_offsets_for_slice(data, slice_offset, slice_size):
            offsets.append((uuid_offset, slice_offset, slice_size))
    if not offsets:
        return data

    normalized = bytearray(data)
    for uuid_offset, _, _ in offsets:
        normalized[uuid_offset:uuid_offset + 16] = bytes(16)
    neutral_digest = hashlib.sha256(normalized).digest()
    for uuid_offset, slice_offset, slice_size in offsets:
        value = bytearray(
            hashlib.sha256(
                neutral_digest + struct.pack(">QQ", slice_offset, slice_size)
            ).digest()[:16]
        )
        value[6] = (value[6] & 0x0F) | 0x50
        value[8] = (value[8] & 0x3F) | 0x80
        normalized[uuid_offset:uuid_offset + 16] = value
    return bytes(normalized)


def normalize_file(path: Path, check_only: bool) -> None:
    path_stat = path.lstat()
    if not stat.S_ISREG(path_stat.st_mode) or path.is_symlink() \
        or path_stat.st_nlink != 1:
        raise MachOError(f"Mach-O path must be a regular non-linked file: {path}")
    if path_stat.st_size <= 0 or path_stat.st_size > MAX_FILE_BYTES:
        raise MachOError(f"Mach-O path has an unsafe size: {path}")
    original = path.read_bytes()
    normalized = normalized_macho_bytes(original)
    if check_only:
        if normalized != original:
            raise MachOError(f"Mach-O UUID is not deterministic: {path}")
        return
    if normalized == original:
        return

    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=path.parent, prefix=f".{path.name}.", delete=False
        ) as handle:
            temporary = Path(handle.name)
            handle.write(normalized)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, stat.S_IMODE(path_stat.st_mode))
        current = path.lstat()
        if (current.st_dev, current.st_ino, current.st_size, current.st_nlink) != (
            path_stat.st_dev,
            path_stat.st_ino,
            path_stat.st_size,
            1,
        ):
            raise MachOError(f"Mach-O path changed during normalization: {path}")
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("paths", nargs="+", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        for path in args.paths:
            normalize_file(path, args.check)
    except (MachOError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
