#!/usr/bin/env python3
"""Unit tests for deterministic thin and fat Mach-O UUID normalization."""

from __future__ import annotations

import struct
import unittest

from normalize_macho_uuid import MachOError, normalized_macho_bytes

LC_UUID = 0x1B


def thin_macho(uuid_bytes: bytes, payload: bytes = b"payload") -> bytes:
    command = struct.pack("<II16s", LC_UUID, 24, uuid_bytes)
    header = struct.pack(
        "<IIIIIIII",
        0xFEEDFACF,
        0x01000007,
        3,
        6,
        1,
        len(command),
        0,
        0,
    )
    return header + command + payload


def fat_macho(first: bytes, second: bytes) -> bytes:
    first_offset = 8 + 2 * 20
    second_offset = first_offset + len(first)
    header = struct.pack(">II", 0xCAFEBABE, 2)
    arches = b"".join(
        [
            struct.pack(">IIIII", 0x01000007, 3, first_offset, len(first), 0),
            struct.pack(">IIIII", 0x01000007, 3, second_offset, len(second), 0),
        ]
    )
    return header + arches + first + second


class NormalizeMachoUuidTests(unittest.TestCase):
    def test_thin_uuid_is_recomputed_from_uuid_neutral_content(self) -> None:
        first = thin_macho(b"a" * 16)
        second = thin_macho(b"b" * 16)
        normalized_first = normalized_macho_bytes(first)
        normalized_second = normalized_macho_bytes(second)
        self.assertEqual(normalized_first, normalized_second)
        self.assertNotEqual(normalized_first, first)
        self.assertEqual(normalized_macho_bytes(normalized_first), normalized_first)

    def test_fat_slices_get_deterministic_distinct_uuids(self) -> None:
        first = fat_macho(thin_macho(b"a" * 16), thin_macho(b"b" * 16))
        second = fat_macho(thin_macho(b"c" * 16), thin_macho(b"d" * 16))
        normalized_first = normalized_macho_bytes(first)
        normalized_second = normalized_macho_bytes(second)
        self.assertEqual(normalized_first, normalized_second)
        first_uuid = normalized_first.find(struct.pack("<II", LC_UUID, 24)) + 8
        second_uuid = normalized_first.find(
            struct.pack("<II", LC_UUID, 24), first_uuid + 16
        ) + 8
        self.assertNotEqual(
            normalized_first[first_uuid:first_uuid + 16],
            normalized_first[second_uuid:second_uuid + 16],
        )

    def test_rejects_non_macho_and_truncated_load_command(self) -> None:
        with self.assertRaises(MachOError):
            normalized_macho_bytes(b"not macho")
        malformed = bytearray(thin_macho(b"a" * 16))
        struct.pack_into("<I", malformed, 36, 4096)
        with self.assertRaises(MachOError):
            normalized_macho_bytes(bytes(malformed))


if __name__ == "__main__":
    unittest.main()
