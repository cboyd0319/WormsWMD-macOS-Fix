#!/usr/bin/env python3
"""Behavior tests for bounded in-place release ZIP manifest verification."""

from __future__ import annotations

import hashlib
import stat
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

from verify_release_zip import ReleaseZipError, verify_release_zip, zip_entry_type


class VerifyReleaseZipTests(unittest.TestCase):
    @staticmethod
    def manifest(rows: list[tuple[str, bytes, str]]) -> bytes:
        lines = [
            "# WormsWMD manifest v2",
            "# sha256-or-symlink-digest\tsize\tpath",
        ]
        for kind, data, path in rows:
            digest = hashlib.sha256(data).hexdigest()
            prefix = "symlink:" if kind == "symlink" else ""
            lines.append(f"{prefix}{digest}\t{len(data)}\t{path}")
        return ("\n".join(lines) + "\n").encode()

    @staticmethod
    def write_zip(
        path: Path,
        rows: list[tuple[str, bytes, str]],
        extras: list[tuple[str, bytes]] | None = None,
        file_mode: int = 0o644,
    ) -> None:
        root = f"{path.stem}/"
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            directory = zipfile.ZipInfo(root)
            directory.external_attr = (stat.S_IFDIR | 0o755) << 16
            archive.writestr(directory, b"")
            for kind, data, rel in rows:
                info = zipfile.ZipInfo(root + rel)
                file_type = stat.S_IFLNK if kind == "symlink" else stat.S_IFREG
                info.external_attr = (file_type | file_mode) << 16
                archive.writestr(info, data)
            manifest = zipfile.ZipInfo(root + "RELEASE_MANIFEST.tsv")
            manifest.external_attr = (stat.S_IFREG | 0o644) << 16
            archive.writestr(manifest, VerifyReleaseZipTests.manifest(rows))
            for name, data in extras or []:
                archive.writestr(name, data)

    def test_accepts_complete_manifest_matching_expected_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            archive = parent / "WormsWMD-macOS-Fix-test.zip"
            rows = [("file", b"payload\n", "payload.txt")]
            self.write_zip(
                archive,
                rows,
            )
            expected = parent / archive.stem
            expected.mkdir()
            (expected / "payload.txt").write_bytes(b"payload\n")
            (expected / "RELEASE_MANIFEST.tsv").write_bytes(self.manifest(rows))
            result = verify_release_zip(archive, expected)
            self.assertEqual(result["root"], "WormsWMD-macOS-Fix-test")
            self.assertEqual(result["entries"], 1)

    def test_rejects_file_without_unix_mode_metadata(self) -> None:
        info = zipfile.ZipInfo("payload.txt")
        info.create_system = 0
        info.external_attr = 0x20
        with self.assertRaises(ReleaseZipError):
            zip_entry_type(info)

    def test_rejects_mismatch_extra_traversal_and_escaping_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mismatch = root / "WormsWMD-macOS-Fix-mismatch.zip"
            self.write_zip(mismatch, [("file", b"payload", "payload.txt")])
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(mismatch, "a") as archive:
                    archive.writestr(
                        "WormsWMD-macOS-Fix-test/payload.txt", b"changed"
                    )
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(mismatch)

            extra = root / "WormsWMD-macOS-Fix-extra.zip"
            self.write_zip(
                extra,
                [("file", b"payload", "payload.txt")],
                [(f"{extra.stem}/extra.txt", b"extra")],
            )
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(extra)

            traversal = root / "WormsWMD-macOS-Fix-traversal.zip"
            self.write_zip(
                traversal,
                [("file", b"payload", "payload.txt")],
                [("../outside", b"escape")],
            )
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(traversal)

            escaping_link = root / "WormsWMD-macOS-Fix-escaping-link.zip"
            self.write_zip(
                escaping_link,
                [("symlink", b"../../outside", "current.txt")],
            )
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(escaping_link)

            contained_link = root / "WormsWMD-macOS-Fix-contained-link.zip"
            self.write_zip(
                contained_link,
                [
                    ("file", b"payload", "payload.txt"),
                    ("symlink", b"payload.txt", "current.txt"),
                ],
            )
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(contained_link)

            unsafe_mode = root / "WormsWMD-macOS-Fix-unsafe-mode.zip"
            self.write_zip(
                unsafe_mode,
                [("file", b"payload", "payload.txt")],
                file_mode=0o664,
            )
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(unsafe_mode)

            hidden_directory_data = root / "WormsWMD-macOS-Fix-dir-data.zip"
            self.write_zip(
                hidden_directory_data,
                [("file", b"payload", "payload.txt")],
                [(f"{hidden_directory_data.stem}/hidden/", b"hidden")],
            )
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(hidden_directory_data)

            archive_comment = root / "WormsWMD-macOS-Fix-comment.zip"
            self.write_zip(archive_comment, [("file", b"payload", "payload.txt")])
            with zipfile.ZipFile(archive_comment, "a") as commented:
                commented.comment = b"unverified metadata"
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(archive_comment)

    def test_rejects_artifact_content_that_differs_from_expected_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            archive = parent / "WormsWMD-macOS-Fix-source-check.zip"
            rows = [("file", b"artifact", "payload.txt")]
            self.write_zip(archive, rows)
            expected = parent / archive.stem
            expected.mkdir()
            (expected / "payload.txt").write_bytes(b"source")
            (expected / "RELEASE_MANIFEST.tsv").write_bytes(self.manifest(rows))
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(archive, expected)

            (expected / "payload.txt").write_bytes(b"artifact")
            (expected / "RELEASE_MANIFEST.tsv").chmod(0o600)
            with self.assertRaises(ReleaseZipError):
                verify_release_zip(archive, expected)


if __name__ == "__main__":
    unittest.main()
