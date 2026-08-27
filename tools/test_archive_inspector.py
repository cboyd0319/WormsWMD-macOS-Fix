#!/usr/bin/env python3
"""Behavior tests for bounded tar.gz archive inspection."""

from __future__ import annotations

import gzip
import hashlib
import importlib.util
import io
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSPECTOR_PATH = ROOT / "tools" / "inspect_archive.py"


def load_inspector():
    spec = importlib.util.spec_from_file_location(
        "wormswmd_archive_inspector", INSPECTOR_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load archive inspector module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def regular(name: str, data: bytes = b"data\n", mode: int = 0o644) -> tarfile.TarInfo:
    member = tarfile.TarInfo(name)
    member.size = len(data)
    member.mode = mode
    return member


def directory(name: str) -> tarfile.TarInfo:
    member = tarfile.TarInfo(name)
    member.type = tarfile.DIRTYPE
    member.mode = 0o755
    return member


def symlink(name: str, target: str) -> tarfile.TarInfo:
    member = tarfile.TarInfo(name)
    member.type = tarfile.SYMTYPE
    member.linkname = target
    member.mode = 0o777
    return member


class ArchiveInspectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.inspector = load_inspector()

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.temp = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_archive(
        self, name: str, members: list[tuple[tarfile.TarInfo, bytes | None]]
    ) -> Path:
        path = self.temp / name
        with tarfile.open(path, "w:gz", format=tarfile.USTAR_FORMAT) as archive:
            for member, data in members:
                source = None if data is None else io.BytesIO(data)
                archive.addfile(member, source)
        return path

    def write_raw_archive(self, name: str, member: tarfile.TarInfo) -> Path:
        header = member.tobuf(
            format=tarfile.USTAR_FORMAT,
            encoding="utf-8",
            errors="surrogateescape",
        )
        path = self.temp / name
        with gzip.open(path, "wb") as compressed:
            compressed.write(header)
            compressed.write(b"\0" * 1024)
        return path

    def limits(self, **overrides):
        values = {
            "max_compressed_bytes": 1024 * 1024,
            "max_expanded_bytes": 1024 * 1024,
            "max_members": 100,
            "max_member_bytes": 512 * 1024,
            "max_ratio": 1000.0,
        }
        values.update(overrides)
        return self.inspector.Limits(**values)

    def inspect(self, path: Path, limits=None, allow_symlinks: bool = False):
        return self.inspector.inspect_archive(
            path,
            limits or self.limits(),
            allow_symlinks=allow_symlinks,
        )

    def assert_rejected(
        self,
        path: Path,
        expected: str,
        *,
        limits=None,
        allow_symlinks: bool = False,
    ) -> None:
        with self.assertRaisesRegex(self.inspector.ArchiveInspectionError, expected):
            self.inspect(path, limits=limits, allow_symlinks=allow_symlinks)

    def test_accepts_valid_qt_style_relative_symlink(self) -> None:
        path = self.write_archive(
            "valid.tar.gz",
            [
                (directory("Frameworks"), None),
                (directory("Frameworks/QtCore.framework"), None),
                (directory("Frameworks/QtCore.framework/Versions"), None),
                (directory("Frameworks/QtCore.framework/Versions/5"), None),
                (
                    regular(
                        "Frameworks/QtCore.framework/Versions/5/QtCore", b"macho"
                    ),
                    b"macho",
                ),
                (symlink("Frameworks/QtCore.framework/QtCore", "Versions/5/QtCore"), None),
            ],
        )

        summary = self.inspect(path, allow_symlinks=True)

        self.assertEqual(summary.members, 6)
        self.assertEqual(summary.regular_files, 1)
        self.assertEqual(summary.symlinks, 1)
        self.assertEqual(summary.expanded_bytes, 5)

    def test_accepts_legacy_tar_root_prefix_without_aliasing(self) -> None:
        path = self.write_archive(
            "legacy-dot-root.tar.gz",
            [
                (directory("."), None),
                (regular("./Team17/save.dat", b"save"), b"save"),
            ],
        )

        summary = self.inspect(path, self.limits(), allow_symlinks=False)

        self.assertEqual(summary.regular_files, 1)

        root_file = self.write_archive(
            "legacy-dot-root-file.tar.gz", [(regular(".", b"replace"), b"replace")]
        )
        self.assert_rejected(root_file, "root|path")

    def test_enforces_compressed_size_at_exact_boundary(self) -> None:
        path = self.write_archive("compressed.tar.gz", [(regular("file"), b"data\n")])
        size = path.stat().st_size

        self.inspect(path, self.limits(max_compressed_bytes=size))
        self.assert_rejected(
            path,
            "compressed size",
            limits=self.limits(max_compressed_bytes=size - 1),
        )

    def test_enforces_total_expanded_size_at_exact_boundary(self) -> None:
        path = self.write_archive(
            "expanded.tar.gz",
            [(regular("one", b"1234"), b"1234"), (regular("two", b"5678"), b"5678")],
        )

        self.inspect(path, self.limits(max_expanded_bytes=8))
        self.assert_rejected(
            path,
            "expanded size",
            limits=self.limits(max_expanded_bytes=7),
        )

    def test_enforces_member_count_at_exact_boundary(self) -> None:
        path = self.write_archive(
            "members.tar.gz",
            [(regular("one", b"1"), b"1"), (regular("two", b"2"), b"2")],
        )

        self.inspect(path, self.limits(max_members=2))
        self.assert_rejected(path, "member count", limits=self.limits(max_members=1))

    def test_bottle_profile_retains_bounded_real_lock_headroom(self) -> None:
        self.assertEqual(
            self.inspector.PROFILES["bottle"].limits.max_members,
            16_384,
        )

    def test_rejects_declared_oversize_before_payload_allocation(self) -> None:
        member = regular("huge", b"")
        member.size = 50_000_000
        path = self.write_raw_archive("declared-huge.tar.gz", member)

        self.assert_rejected(
            path,
            "member size",
            limits=self.limits(
                max_expanded_bytes=100_000_000,
                max_member_bytes=1024,
            ),
        )

    def test_enforces_compression_ratio(self) -> None:
        payload = b"0" * 32_768
        path = self.write_archive("ratio.tar.gz", [(regular("zeros", payload), payload)])
        actual_ratio = len(payload) / path.stat().st_size

        self.inspect(path, self.limits(max_ratio=actual_ratio + 1.0))
        self.assert_rejected(
            path,
            "compression ratio",
            limits=self.limits(max_ratio=actual_ratio - 0.1),
        )

    def test_rejects_duplicate_and_canonical_aliases(self) -> None:
        duplicate = self.write_archive(
            "duplicate.tar.gz",
            [(regular("same", b"1"), b"1"), (regular("same", b"2"), b"2")],
        )
        alias = self.write_archive(
            "alias.tar.gz",
            [(regular("Dir/File", b"1"), b"1"), (regular("dir/file", b"2"), b"2")],
        )

        self.assert_rejected(duplicate, "duplicate")
        self.assert_rejected(alias, "canonical duplicate")

    def test_rejects_unsafe_and_noncanonical_paths(self) -> None:
        names = [
            "/absolute",
            "../escape",
            "safe/../../escape",
            "safe//double",
            "safe/./dot",
            "././double-dot-prefix",
            "C:/windows",
            "safe\\windows",
            "control\nname",
            "zero\u200bwidth",
            "e\u0301",
        ]
        for index, name in enumerate(names):
            with self.subTest(name=name):
                path = self.write_archive(
                    f"unsafe-{index}.tar.gz", [(regular(name, b"x"), b"x")]
                )
                self.assert_rejected(path, "path")

    def test_rejects_invalid_utf8_surrogate_name(self) -> None:
        member = regular("invalid-\udcff", b"")
        path = self.write_raw_archive("invalid-utf8.tar.gz", member)

        self.assert_rejected(path, "Unicode|path")

    def test_rejects_links_and_escaping_symlink_targets(self) -> None:
        hardlink = tarfile.TarInfo("hard")
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = "target"
        hardlink_path = self.write_archive("hardlink.tar.gz", [(hardlink, None)])
        symlink_path = self.write_archive(
            "symlink.tar.gz", [(symlink("dir/link", "../../outside"), None)]
        )

        self.assert_rejected(hardlink_path, "unsupported.*hard link|hard link")
        self.assert_rejected(symlink_path, "symlink", allow_symlinks=False)
        self.assert_rejected(
            symlink_path, "escapes", allow_symlinks=True
        )

    def test_rejects_special_sparse_and_privileged_modes(self) -> None:
        fifo = tarfile.TarInfo("fifo")
        fifo.type = tarfile.FIFOTYPE
        sparse = tarfile.TarInfo("sparse")
        sparse.type = tarfile.GNUTYPE_SPARSE
        privileged = regular("setuid", b"x", mode=0o4755)

        for name, member, data, expected in [
            ("fifo.tar.gz", fifo, None, "unsupported"),
            ("sparse.tar.gz", sparse, None, "sparse|unsupported"),
            ("setuid.tar.gz", privileged, b"x", "permission|mode"),
        ]:
            with self.subTest(name=name):
                if member.type == tarfile.GNUTYPE_SPARSE:
                    path = self.write_raw_archive(name, member)
                else:
                    path = self.write_archive(name, [(member, data)])
                self.assert_rejected(path, expected)

    def test_rejects_truncated_gzip(self) -> None:
        path = self.write_archive("truncated.tar.gz", [(regular("file"), b"data\n")])
        path.write_bytes(path.read_bytes()[:-8])

        self.assert_rejected(path, "gzip|tar|truncated|archive")

    def test_cli_reports_profile_summary_and_rejects_unknown_profile(self) -> None:
        path = self.write_archive("cli.tar.gz", [(regular("file"), b"data\n")])
        result = subprocess.run(
            [sys.executable, str(INSPECTOR_PATH), "--profile", "qt", str(path)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        unknown = subprocess.run(
            [sys.executable, str(INSPECTOR_PATH), "--profile", "unknown", str(path)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("profile=qt", result.stdout)
        self.assertNotEqual(unknown.returncode, 0)

    def test_cli_bounded_copy_is_owner_only_and_digest_bound(self) -> None:
        path = self.write_archive("copy-source.tar.gz", [(regular("file"), b"data\n")])
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        copied = self.temp / "copied.tar.gz"
        result = subprocess.run(
            [
                sys.executable,
                str(INSPECTOR_PATH),
                "--profile",
                "qt",
                "--copy-to",
                str(copied),
                "--expected-sha256",
                expected,
                "--quiet",
                str(path),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(copied.read_bytes(), path.read_bytes())
        self.assertEqual(copied.stat().st_mode & 0o777, 0o600)
        self.assertEqual(copied.stat().st_nlink, 1)

        mismatch = self.temp / "mismatch.tar.gz"
        rejected = subprocess.run(
            [
                sys.executable,
                str(INSPECTOR_PATH),
                "--profile",
                "qt",
                "--copy-to",
                str(mismatch),
                "--expected-sha256",
                "0" * 64,
                "--quiet",
                str(path),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertFalse(mismatch.exists())


if __name__ == "__main__":
    unittest.main()
