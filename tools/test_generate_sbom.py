#!/usr/bin/env python3
"""Behavior tests for the deterministic CycloneDX release SBOM generator."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GENERATOR = ROOT / "tools" / "generate_sbom.py"
PROVENANCE = ROOT / "dist" / "qt-frameworks-x86_64-5.15.19.source-provenance.tsv"
CHECKSUM = ROOT / "dist" / "qt-frameworks-x86_64-5.15.19.tar.gz.sha256"
TIMESTAMP = "2026-08-26T12:34:56Z"


class GenerateSbomTests(unittest.TestCase):
    def run_generator(
        self, output: Path, *extra: str
    ) -> subprocess.CompletedProcess[str]:
        release_checksum = output.parent / "release.zip.sha256"
        release_checksum.write_text("f" * 64 + "  release.zip\n", encoding="utf-8")
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
                *extra,
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )

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
            expected_count = (
                sum(
                    1
                    for line in PROVENANCE.read_text(encoding="utf-8").splitlines()
                    if line and not line.startswith("#")
                )
                - 1
            )
            self.assertEqual(len(components), expected_count)
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
                "f" * 64,
            )
            properties = {
                item["name"]: item["value"]
                for item in document["metadata"]["properties"]
            }
            self.assertEqual(
                properties["wormswmd:qt-archive-sha256"],
                CHECKSUM.read_text(encoding="utf-8").split()[0],
            )

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
            checksum.write_text("e" * 64 + "  archive.tar.gz\n", encoding="utf-8")

            result = self.run_generator(
                output,
                "--provenance",
                str(lock),
                "--archive-checksum",
                str(checksum),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
