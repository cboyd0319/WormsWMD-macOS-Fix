#!/usr/bin/env python3
"""Behavior tests for the deterministic CycloneDX release SBOM generator."""

from __future__ import annotations

import hashlib
import io
import json
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GENERATOR = ROOT / "tools" / "generate_sbom.py"
PROVENANCE = ROOT / "dist" / "qt-frameworks-x86_64-5.15.19.source-provenance.tsv"
CHECKSUM = ROOT / "dist" / "qt-frameworks-x86_64-5.15.19.tar.gz.sha256"
TIMESTAMP = "2026-08-26T12:34:56Z"


class GenerateSbomTests(unittest.TestCase):
    @staticmethod
    def write_archive(path: Path, provenance: bytes) -> None:
        with tarfile.open(path, "w:gz") as archive:
            member = tarfile.TarInfo("SOURCE_PROVENANCE.tsv")
            member.size = len(provenance)
            member.mode = 0o644
            archive.addfile(member, io.BytesIO(provenance))

    def run_generator(
        self, output: Path, *extra: str
    ) -> subprocess.CompletedProcess[str]:
        release_archive = output.parent / "release.zip"
        release_checksum = output.parent / "release.zip.sha256"
        release_archive.write_bytes(b"deterministic release fixture\n")
        release_hash = hashlib.sha256(release_archive.read_bytes()).hexdigest()
        release_checksum.write_text(release_hash + "  release.zip\n", encoding="utf-8")
        return subprocess.run(
            [
                sys.executable,
                str(GENERATOR),
                "--version",
                "v1.7.6",
                "--timestamp",
                TIMESTAMP,
                "--output",
                str(output),
                "--release-checksum",
                str(release_checksum),
                "--release-archive",
                str(release_archive),
                *extra,
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )

    @staticmethod
    def run_inventory(output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(GENERATOR),
                "--inventory-only",
                "--version",
                "v1.7.6",
                "--timestamp",
                TIMESTAMP,
                "--output",
                str(output),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_archive_provenance_verification_is_streaming(self) -> None:
        source = GENERATOR.read_text(encoding="utf-8")
        self.assertNotIn(".getmembers(", source)
        self.assertIn("inspect_archive(", source)

    def test_real_lock_produces_deterministic_complete_inventory(self) -> None:
        self.assertTrue(GENERATOR.is_file(), "tools/generate_sbom.py is required")
        with tempfile.TemporaryDirectory() as temporary_directory:
            temp = Path(temporary_directory)
            first = temp / "first.cdx.json"
            second = temp / "second.cdx.json"

            first_run = self.run_generator(first)
            second_run = self.run_generator(second)
            self.assertEqual(first_run.returncode, 0, first_run.stderr)
            self.assertEqual(second_run.returncode, 0, second_run.stderr)
            self.assertEqual(first.read_bytes(), second.read_bytes())

            document = json.loads(first.read_text(encoding="utf-8"))
            self.assertEqual(document["bomFormat"], "CycloneDX")
            self.assertEqual(document["specVersion"], "1.6")
            self.assertEqual(document["metadata"]["timestamp"], TIMESTAMP)
            self.assertEqual(document["metadata"]["component"]["version"], "v1.7.6")

            components = document["components"]
            provenance_names = {
                line.split("\t", 1)[0]
                for line in PROVENANCE.read_text(encoding="utf-8").splitlines()
                if line and not line.startswith("#") and not line.startswith("name\t")
            }
            build_components = document["formulation"][0]["components"]
            self.assertEqual(len(components), 12)
            self.assertEqual(len(build_components), 5)
            self.assertEqual(
                {component["name"] for component in components + build_components},
                provenance_names,
            )
            self.assertTrue(
                all(component["scope"] == "required" for component in components)
            )
            self.assertTrue(
                all(component["scope"] == "excluded" for component in build_components)
            )
            self.assertTrue(all(component.get("cpe") for component in components))
            refs = [component["bom-ref"] for component in components]
            self.assertEqual(len(refs), len(set(refs)))
            self.assertTrue(
                all(
                    component["hashes"][0]["alg"] == "SHA-256"
                    for component in components
                )
            )

            root_ref = document["metadata"]["component"]["bom-ref"]
            root_dependency = next(
                item for item in document["dependencies"] if item["ref"] == root_ref
            )
            self.assertEqual(sorted(root_dependency["dependsOn"]), sorted(refs))
            self.assertEqual(
                document["metadata"]["component"]["hashes"][0]["content"],
                hashlib.sha256(b"deterministic release fixture\n").hexdigest(),
            )
            properties = {
                item["name"]: item["value"]
                for item in document["metadata"]["properties"]
            }
            self.assertEqual(
                properties["wormswmd:qt-archive-sha256"],
                CHECKSUM.read_text(encoding="utf-8").split()[0],
            )

    def test_inventory_only_output_is_deterministic_and_scannable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temp = Path(temporary_directory)
            first = temp / "first.cdx.json"
            second = temp / "second.cdx.json"
            first_run = self.run_inventory(first)
            second_run = self.run_inventory(second)
            self.assertEqual(first_run.returncode, 0, first_run.stderr)
            self.assertEqual(second_run.returncode, 0, second_run.stderr)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            document = json.loads(first.read_text(encoding="utf-8"))
            self.assertEqual(
                document["metadata"]["component"]["name"], "WormsWMD Qt Runtime"
            )
            self.assertEqual(len(document["components"]), 12)
            self.assertEqual(len(document["formulation"][0]["components"]), 5)

    def test_rejects_unsafe_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "bad.cdx.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "--version",
                    "../1.7.6",
                    "--timestamp",
                    TIMESTAMP,
                    "--output",
                    str(output),
                    "--release-archive",
                    str(output.parent / "missing.zip"),
                    "--release-checksum",
                    str(output.parent / "missing.zip.sha256"),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_rejects_duplicate_lock_components(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temp = Path(temporary_directory)
            lock = temp / "duplicate.tsv"
            checksum = temp / "archive.sha256"
            archive = temp / "archive.tar.gz"
            output = temp / "bad.cdx.json"
            header = "name\tversion\tbottle_tag\tbottle_sha256\tbottle_url\tsource_sha256\truby_source_sha256\ttap_git_head\n"
            row = (
                "demo\t1.0\tsonoma\t"
                + "a" * 64
                + "\thttps://example.invalid/demo.tgz\t"
                + "b" * 64
                + "\t"
                + "c" * 64
                + "\t"
                + "d" * 40
                + "\n"
            )
            lock.write_text(header + row + row, encoding="utf-8")
            self.write_archive(archive, lock.read_bytes())
            archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
            checksum.write_text(archive_hash + "  archive.tar.gz\n", encoding="utf-8")

            result = self.run_generator(
                output,
                "--provenance",
                str(lock),
                "--archive-checksum",
                str(checksum),
                "--archive",
                str(archive),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Duplicate component name", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_lock_that_differs_from_embedded_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temp = Path(temporary_directory)
            archive = temp / "archive.tar.gz"
            checksum = temp / "archive.sha256"
            output = temp / "bad.cdx.json"
            embedded = PROVENANCE.read_bytes() + b"# unexpected archive-only change\n"
            self.write_archive(archive, embedded)
            archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
            checksum.write_text(archive_hash + "  archive.tar.gz\n", encoding="utf-8")

            result = self.run_generator(
                output,
                "--archive",
                str(archive),
                "--archive-checksum",
                str(checksum),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not match", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_release_zip_that_differs_from_its_checksum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temp = Path(temporary_directory)
            output = temp / "bad.cdx.json"
            release_archive = temp / "release.zip"
            release_checksum = temp / "release.zip.sha256"
            release_archive.write_bytes(b"release contents\n")
            release_checksum.write_text("f" * 64 + "  release.zip\n", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "--version",
                    "v1.7.6",
                    "--timestamp",
                    TIMESTAMP,
                    "--output",
                    str(output),
                    "--release-archive",
                    str(release_archive),
                    "--release-checksum",
                    str(release_checksum),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Release zip does not match", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_checksum_for_a_different_release_filename(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temp = Path(temporary_directory)
            output = temp / "bad.cdx.json"
            release_archive = temp / "release.zip"
            release_checksum = temp / "release.zip.sha256"
            release_archive.write_bytes(b"release contents\n")
            digest = hashlib.sha256(release_archive.read_bytes()).hexdigest()
            release_checksum.write_text(
                digest + "  different-release.zip\n", encoding="utf-8"
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "--version",
                    "v1.7.6",
                    "--timestamp",
                    TIMESTAMP,
                    "--output",
                    str(output),
                    "--release-archive",
                    str(release_archive),
                    "--release-checksum",
                    str(release_checksum),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("checksum record", result.stderr.lower())
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
