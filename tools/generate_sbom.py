#!/usr/bin/env python3
"""Generate a deterministic CycloneDX SBOM from the locked Qt bottle closure."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import tarfile
import tempfile
import uuid
from collections.abc import Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlparse

from inspect_archive import ArchiveInspectionError, PROFILES, copy_and_inspect_archive
from qt_component_policy import (
    QtPolicyError,
    read_component_policy,
    validate_component_policy,
)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PROVENANCE = (
    ROOT / "dist" / "qt-frameworks-x86_64-5.15.19.source-provenance.tsv"
)
DEFAULT_ARCHIVE = ROOT / "dist" / "qt-frameworks-x86_64-5.15.19.tar.gz"
DEFAULT_CHECKSUM = ROOT / "dist" / "qt-frameworks-x86_64-5.15.19.tar.gz.sha256"
DEFAULT_POLICY = ROOT / "packaging" / "qt-component-policy.tsv"
EXPECTED_HEADER = [
    "name",
    "version",
    "bottle_tag",
    "bottle_sha256",
    "bottle_url",
    "source_sha256",
    "ruby_source_sha256",
    "tap_git_head",
]
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
VERSION_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
NAME_RE = re.compile(r"^[A-Za-z0-9@+_.\-/]+$")
MAX_PROVENANCE_BYTES = 1_048_576
MAX_ARCHIVE_BYTES = 268_435_456
MAX_CHECKSUM_BYTES = 4_096
MAX_COMPONENTS = 1_000
GENERATOR_VERSION = "1"


class SbomError(ValueError):
    """Raised when provenance or CLI input cannot produce a trustworthy SBOM."""


def read_bounded_file(path: Path, max_bytes: int, label: str) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise SbomError(f"{label} must be a regular file: {path}")
    with path.open("rb") as source:
        data = source.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise SbomError(f"{label} exceeds the size limit")
    return data


def normalize_timestamp(value: str) -> str:
    candidate = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError as error:
        raise SbomError(f"Invalid ISO-8601 timestamp: {value}") from error
    if parsed.tzinfo is None:
        raise SbomError("SBOM timestamp must include a timezone")
    return (
        parsed.astimezone(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )


def require_sha256(value: str, field: str) -> str:
    if not SHA256_RE.fullmatch(value):
        raise SbomError(f"Invalid {field}: expected lowercase SHA-256")
    return value


def read_checksum(path: Path, expected_suffix: str, label: str) -> str:
    checksum_bytes = read_bounded_file(
        path, MAX_CHECKSUM_BYTES, f"{label} checksum file"
    )
    lines = [
        line for line in checksum_bytes.decode("utf-8").splitlines() if line.strip()
    ]
    if len(lines) != 1:
        raise SbomError(f"{label} checksum file must contain exactly one record")
    fields = lines[0].split()
    if len(fields) != 2 or not fields[1].endswith(expected_suffix):
        raise SbomError(
            f"Checksum record must contain SHA-256 and {expected_suffix} filename"
        )
    return require_sha256(fields[0], f"{label} checksum")


def verify_file_sha256(path: Path, expected_sha256: str, label: str) -> None:
    if not path.is_file() or path.is_symlink():
        raise SbomError(f"{label} must be a regular file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1_048_576), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha256:
        raise SbomError(f"{label} does not match its checksum file")


def verify_archive_provenance(
    archive_path: Path, expected_sha256: str, provenance: bytes
) -> set[str]:
    if not archive_path.is_file() or archive_path.is_symlink():
        raise SbomError(f"Qt archive must be a regular file: {archive_path}")
    if archive_path.stat().st_size > MAX_ARCHIVE_BYTES:
        raise SbomError("Qt archive exceeds the size limit")

    embedded: bytes | None = None
    regular_members: set[str] = set()
    with tempfile.TemporaryDirectory(prefix="wormswmd-sbom-archive-") as directory:
        inspected_archive = Path(directory) / "qt-package.tar.gz"
        profile = PROFILES["qt"]
        try:
            copy_and_inspect_archive(
                archive_path,
                inspected_archive,
                profile.limits,
                allow_symlinks=profile.allow_symlinks,
                expected_sha256=expected_sha256,
            )
            with tarfile.open(inspected_archive, "r|gz") as archive:
                for member in archive:
                    if member.isfile():
                        regular_members.add(member.name)
                    if member.name != "SOURCE_PROVENANCE.tsv":
                        continue
                    if embedded is not None or not member.isfile():
                        raise SbomError(
                            "Qt archive must contain exactly one regular "
                            "SOURCE_PROVENANCE.tsv"
                        )
                    if member.size > MAX_PROVENANCE_BYTES:
                        raise SbomError("Embedded provenance lock exceeds the size limit")
                    embedded_file = archive.extractfile(member)
                    if embedded_file is None:
                        raise SbomError("Could not read embedded provenance lock")
                    embedded = embedded_file.read(MAX_PROVENANCE_BYTES + 1)
        except ArchiveInspectionError as error:
            raise SbomError(f"Qt archive safety inspection failed: {error}") from error
        except tarfile.TarError as error:
            raise SbomError(f"Could not read Qt archive: {error}") from error

    if embedded is None:
        raise SbomError(
            "Qt archive must contain exactly one regular SOURCE_PROVENANCE.tsv"
        )

    if embedded != provenance:
        raise SbomError(
            "Standalone provenance lock does not match the copy embedded in the Qt archive"
        )
    return regular_members


def read_provenance(path: Path) -> tuple[list[dict[str, str]], bytes]:
    provenance = read_bounded_file(path, MAX_PROVENANCE_BYTES, "Provenance lock")

    data_lines = [
        line
        for line in provenance.decode("utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    if not data_lines:
        raise SbomError("Provenance lock is empty")

    reader = csv.DictReader(data_lines, delimiter="\t")
    if reader.fieldnames != EXPECTED_HEADER:
        raise SbomError("Provenance lock header does not match the supported schema")

    rows: list[dict[str, str]] = []
    names: set[str] = set()
    for raw_row in reader:
        if len(rows) >= MAX_COMPONENTS:
            raise SbomError("Provenance lock exceeds the component limit")
        if None in raw_row or any(value is None for value in raw_row.values()):
            raise SbomError("Malformed provenance row")
        row = {key: value.strip() for key, value in raw_row.items()}
        if any(not row[field] for field in EXPECTED_HEADER):
            raise SbomError("Provenance rows may not contain empty fields")
        if not NAME_RE.fullmatch(row["name"]):
            raise SbomError(f"Invalid component name: {row['name']}")
        if row["name"] in names:
            raise SbomError(f"Duplicate component name: {row['name']}")
        names.add(row["name"])
        if len(row["version"]) > 128 or any(ord(char) < 32 for char in row["version"]):
            raise SbomError(f"Invalid component version for {row['name']}")
        parsed_url = urlparse(row["bottle_url"])
        if parsed_url.scheme != "https" or not parsed_url.hostname:
            raise SbomError(f"Bottle URL must use HTTPS for {row['name']}")
        require_sha256(row["bottle_sha256"], f"bottle checksum for {row['name']}")
        require_sha256(row["source_sha256"], f"source checksum for {row['name']}")
        require_sha256(row["ruby_source_sha256"], f"formula checksum for {row['name']}")
        if not SHA1_RE.fullmatch(row["tap_git_head"]):
            raise SbomError(f"Invalid Homebrew tap commit for {row['name']}")
        rows.append(row)

    if not rows:
        raise SbomError("Provenance lock contains no components")
    return sorted(rows, key=lambda item: item["name"]), provenance


def component_from_row(
    row: dict[str, str], policy: dict[str, str]
) -> dict[str, Any]:
    encoded_version = quote(row["version"], safe="")
    purl = policy["purl_template"].replace("{version}", encoded_version)
    component: dict[str, Any] = {
        "type": "library",
        "bom-ref": purl,
        "name": row["name"],
        "version": row["version"],
        "supplier": {"name": policy["supplier"]},
        "scope": "required" if policy["scope"] == "runtime" else "excluded",
        "purl": purl,
        "hashes": [{"alg": "SHA-256", "content": row["bottle_sha256"]}],
        "externalReferences": [{"type": "distribution", "url": row["bottle_url"]}],
        "properties": [
            {"name": "wormswmd:homebrew:bottle-tag", "value": row["bottle_tag"]},
            {"name": "wormswmd:homebrew:source-sha256", "value": row["source_sha256"]},
            {
                "name": "wormswmd:homebrew:formula-sha256",
                "value": row["ruby_source_sha256"],
            },
            {"name": "wormswmd:homebrew:tap-commit", "value": row["tap_git_head"]},
            {"name": "wormswmd:component-scope", "value": policy["scope"]},
            {
                "name": "wormswmd:shipped-file-evidence",
                "value": policy["shipped_file_evidence"],
            },
            {
                "name": "wormswmd:identity-source",
                "value": policy["identity_source"],
            },
            {"name": "wormswmd:policy-rationale", "value": policy["rationale"]},
            {"name": "wormswmd:policy-review-date", "value": policy["review_date"]},
            {"name": "wormswmd:policy-owner", "value": policy["owner"]},
        ],
    }
    if policy["cpe_product"] != "unmapped":
        vendor, product = policy["cpe_product"].split(":", 1)
        component["cpe"] = (
            f"cpe:2.3:a:{vendor}:{product}:{row['version']}:*:*:*:*:*:*:*"
        )
    return component


def load_component_inventory(
    provenance_path: Path,
    archive_path: Path,
    checksum_path: Path,
    policy_path: Path,
) -> tuple[str, list[dict[str, str]], list[dict[str, Any]], list[dict[str, Any]]]:
    archive_sha256 = read_checksum(checksum_path, ".tar.gz", "Qt archive")
    rows, provenance = read_provenance(provenance_path)
    archive_members = verify_archive_provenance(
        archive_path, archive_sha256, provenance
    )
    policy_rows = validate_component_policy(
        read_component_policy(policy_path), rows, archive_members
    )
    policy_by_name = {row["name"]: row for row in policy_rows}
    all_components = [
        component_from_row(row, policy_by_name[row["name"]]) for row in rows
    ]
    runtime_components = [
        component
        for component in all_components
        if policy_by_name[component["name"]]["scope"] == "runtime"
    ]
    build_components = [
        component
        for component in all_components
        if policy_by_name[component["name"]]["scope"] == "build"
    ]
    return archive_sha256, rows, runtime_components, build_components


def build_formulation(
    root_ref: str, build_components: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    return [
        {
            "bom-ref": f"{root_ref}:build-inputs",
            "components": build_components,
            "properties": [
                {
                    "name": "wormswmd:formulation-scope",
                    "value": "build-only Homebrew inputs not shipped at runtime",
                }
            ],
        }
    ]


def build_sbom(
    version: str,
    timestamp: str,
    provenance_path: Path,
    archive_path: Path,
    checksum_path: Path,
    release_archive_path: Path,
    release_checksum_path: Path,
    policy_path: Path = DEFAULT_POLICY,
) -> dict[str, Any]:
    if not VERSION_RE.fullmatch(version):
        raise SbomError("Version must use the form vX.Y.Z")
    normalized_timestamp = normalize_timestamp(timestamp)
    release_sha256 = read_checksum(release_checksum_path, ".zip", "Release zip")
    archive_sha256, rows, components, build_components = load_component_inventory(
        provenance_path, archive_path, checksum_path, policy_path
    )
    verify_file_sha256(release_archive_path, release_sha256, "Release zip")
    component_refs = [component["bom-ref"] for component in components]
    root_ref = f"WormsWMD-macOS-Fix@{version}"
    identity = "\n".join(
        [
            version,
            release_sha256,
            archive_sha256,
            *(component["bom-ref"] for component in components + build_components),
            *(row["bottle_sha256"] for row in rows),
        ]
    )
    serial = uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"https://github.com/cboyd0319/WormsWMD-macOS-Fix\n{identity}",
    )

    return {
        "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{serial}",
        "version": 1,
        "metadata": {
            "timestamp": normalized_timestamp,
            "tools": {
                "components": [
                    {
                        "type": "application",
                        "bom-ref": "wormswmd-sbom-generator",
                        "name": "WormsWMD SBOM generator",
                        "version": GENERATOR_VERSION,
                    }
                ]
            },
            "component": {
                "type": "application",
                "bom-ref": root_ref,
                "name": "WormsWMD-macOS-Fix",
                "version": version,
                "hashes": [{"alg": "SHA-256", "content": release_sha256}],
                "externalReferences": [
                    {
                        "type": "vcs",
                        "url": f"https://github.com/cboyd0319/WormsWMD-macOS-Fix/tree/{version}",
                    }
                ],
            },
            "properties": [
                {
                    "name": "wormswmd:provenance-lock",
                    "value": provenance_path.name,
                },
                {
                    "name": "wormswmd:component-policy",
                    "value": policy_path.name,
                },
                {
                    "name": "wormswmd:qt-archive-sha256",
                    "value": archive_sha256,
                },
            ],
        },
        "components": components,
        "dependencies": [
            {"ref": root_ref, "dependsOn": component_refs},
            *({"ref": component_ref} for component_ref in component_refs),
        ],
        "formulation": build_formulation(root_ref, build_components),
    }


def build_inventory_sbom(
    version: str,
    timestamp: str,
    provenance_path: Path,
    archive_path: Path,
    checksum_path: Path,
    policy_path: Path = DEFAULT_POLICY,
) -> dict[str, Any]:
    if not VERSION_RE.fullmatch(version):
        raise SbomError("Version must use the form vX.Y.Z")
    normalized_timestamp = normalize_timestamp(timestamp)
    archive_sha256, rows, components, build_components = load_component_inventory(
        provenance_path, archive_path, checksum_path, policy_path
    )
    qt_version = next(row["version"] for row in rows if row["name"] == "qt@5")
    root_ref = f"WormsWMD-Qt-Runtime@{qt_version}"
    component_refs = [component["bom-ref"] for component in components]
    identity = "\n".join(
        [
            version,
            archive_sha256,
            *(component["bom-ref"] for component in components + build_components),
            *(row["bottle_sha256"] for row in rows),
        ]
    )
    serial = uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"https://github.com/cboyd0319/WormsWMD-macOS-Fix/qt-runtime\n{identity}",
    )
    return {
        "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{serial}",
        "version": 1,
        "metadata": {
            "timestamp": normalized_timestamp,
            "tools": {
                "components": [
                    {
                        "type": "application",
                        "bom-ref": "wormswmd-sbom-generator",
                        "name": "WormsWMD SBOM generator",
                        "version": GENERATOR_VERSION,
                    }
                ]
            },
            "component": {
                "type": "framework",
                "bom-ref": root_ref,
                "name": "WormsWMD Qt Runtime",
                "version": qt_version,
                "hashes": [{"alg": "SHA-256", "content": archive_sha256}],
            },
            "properties": [
                {"name": "wormswmd:source-version", "value": version},
                {"name": "wormswmd:provenance-lock", "value": provenance_path.name},
                {"name": "wormswmd:component-policy", "value": policy_path.name},
                {"name": "wormswmd:qt-archive-sha256", "value": archive_sha256},
            ],
        },
        "components": components,
        "dependencies": [
            {"ref": root_ref, "dependsOn": component_refs},
            *({"ref": component_ref} for component_ref in component_refs),
        ],
        "formulation": build_formulation(root_ref, build_components),
    }


def atomic_write_json(path: Path, document: dict[str, Any]) -> None:
    if path.is_symlink():
        raise SbomError(f"Refusing to replace symlink output: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            json.dump(document, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument(
        "--version", required=True, help="Release version in vX.Y.Z form"
    )
    parser.add_argument(
        "--timestamp", required=True, help="Timezone-aware ISO-8601 build timestamp"
    )
    parser.add_argument(
        "--output", required=True, type=Path, help="CycloneDX JSON output path"
    )
    parser.add_argument(
        "--inventory-only",
        action="store_true",
        help="Describe the Qt runtime/build inventory without a release zip root",
    )
    parser.add_argument(
        "--release-archive",
        type=Path,
        help="Release zip described by the SBOM",
    )
    parser.add_argument(
        "--release-checksum",
        type=Path,
        help="Checksum file for the release zip described by the SBOM",
    )
    parser.add_argument("--provenance", type=Path, default=DEFAULT_PROVENANCE)
    parser.add_argument("--component-policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument("--archive-checksum", type=Path, default=DEFAULT_CHECKSUM)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.inventory_only:
            if args.release_archive is not None or args.release_checksum is not None:
                raise SbomError(
                    "--inventory-only cannot be combined with release zip inputs"
                )
            document = build_inventory_sbom(
                args.version,
                args.timestamp,
                args.provenance,
                args.archive,
                args.archive_checksum,
                args.component_policy,
            )
        else:
            if args.release_archive is None or args.release_checksum is None:
                raise SbomError(
                    "Release SBOM requires --release-archive and --release-checksum"
                )
            document = build_sbom(
                args.version,
                args.timestamp,
                args.provenance,
                args.archive,
                args.archive_checksum,
                args.release_archive,
                args.release_checksum,
                args.component_policy,
            )
        atomic_write_json(args.output, document)
    except (OSError, UnicodeError, SbomError, QtPolicyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
