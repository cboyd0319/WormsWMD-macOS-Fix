#!/usr/bin/env python3
"""Collect and compare deterministic evidence for extracted Qt artifacts."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from normalize_macho_uuid import MachOError, macho_slices

MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_OUTPUT_BYTES = 4 * 1024 * 1024
URL_RE = re.compile(rb"https?://[^\x00-\x20\"'<>]+")


class EvidenceError(ValueError):
    """Raised when artifact evidence cannot be collected or compared safely."""


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_tool(arguments: list[str], allow_failure: bool = False) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        arguments,
        check=False,
        capture_output=True,
        text=True,
        timeout=15,
    )
    if len(result.stdout.encode("utf-8")) > MAX_OUTPUT_BYTES \
        or len(result.stderr.encode("utf-8")) > MAX_OUTPUT_BYTES:
        raise EvidenceError(f"Tool output exceeded limit: {arguments[0]}")
    if result.returncode != 0 and not allow_failure:
        raise EvidenceError(f"Tool failed: {' '.join(arguments[:2])}")
    return result


def macho_dependencies(path: Path) -> list[str]:
    output = run_tool(["/usr/bin/otool", "-arch", "x86_64", "-L", str(path)]).stdout
    dependencies: list[str] = []
    for line in output.splitlines()[1:]:
        candidate = line.strip()
        if not candidate:
            continue
        candidate = re.sub(r"\s+\(compatibility version .*$", "", candidate)
        dependencies.append(candidate)
    return dependencies


def macho_install_id(path: Path) -> str:
    result = run_tool(
        ["/usr/bin/otool", "-arch", "x86_64", "-D", str(path)],
        allow_failure=True,
    )
    return result.stdout.splitlines()[1] if result.returncode == 0 \
        and len(result.stdout.splitlines()) > 1 else ""


def macho_rpaths(path: Path) -> list[str]:
    output = run_tool(["/usr/bin/otool", "-arch", "x86_64", "-l", str(path)]).stdout
    rpaths: list[str] = []
    in_rpath = False
    for raw_line in output.splitlines():
        fields = raw_line.split()
        if fields[:1] == ["cmd"]:
            in_rpath = len(fields) > 1 and fields[1] == "LC_RPATH"
            continue
        if in_rpath and fields[:1] == ["path"]:
            line = raw_line.strip()
            line = re.sub(r"^path\s+", "", line)
            line = re.sub(r"\s+\(offset\s+[0-9]+\)$", "", line)
            rpaths.append(line)
            in_rpath = False
    return rpaths


def signature_evidence(path: Path) -> tuple[str, str]:
    verify = run_tool(
        ["/usr/bin/codesign", "--verify", "--strict", str(path)],
        allow_failure=True,
    )
    if verify.returncode != 0:
        details = run_tool(
            ["/usr/bin/codesign", "-dv", "--verbose=4", str(path)],
            allow_failure=True,
        )
        combined = f"{verify.stderr}\n{details.stderr}"
        state = "unsigned" if re.search(r"not signed|code object is not signed", combined, re.I) \
            else "invalid"
        return state, ""
    details = run_tool(
        ["/usr/bin/codesign", "-dv", "--verbose=4", str(path)],
        allow_failure=True,
    )
    state = "valid-adhoc" if re.search(r"adhoc|ad.?hoc", details.stderr, re.I) \
        else "valid"
    entitlements = run_tool(
        ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)],
        allow_failure=True,
    )
    return state, entitlements.stdout.strip()


def is_macho(path: Path) -> bool:
    with path.open("rb") as source:
        header = source.read(4)
    try:
        macho_slices(header + b"\x00" * 64)
    except MachOError:
        return header in {
            b"\xce\xfa\xed\xfe",
            b"\xcf\xfa\xed\xfe",
            b"\xfe\xed\xfa\xce",
            b"\xfe\xed\xfa\xcf",
            b"\xca\xfe\xba\xbe",
            b"\xbe\xba\xfe\xca",
            b"\xca\xfe\xba\xbf",
            b"\xbf\xba\xfe\xca",
        }
    return True


def collect_tree(root: Path) -> dict[str, Any]:
    if not root.is_dir() or root.is_symlink():
        raise EvidenceError(f"Artifact root must be a non-linked directory: {root}")
    inventory: list[dict[str, Any]] = []
    files: list[dict[str, Any]] = []
    macho: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        rel = path.relative_to(root).as_posix()
        path_stat = path.lstat()
        entry: dict[str, Any] = {
            "path": rel,
            "mode": f"{stat.S_IMODE(path_stat.st_mode):04o}",
        }
        if stat.S_ISLNK(path_stat.st_mode):
            entry.update(type="symlink", target=os.readlink(path))
        elif stat.S_ISDIR(path_stat.st_mode):
            entry["type"] = "directory"
        elif stat.S_ISREG(path_stat.st_mode):
            if path_stat.st_nlink != 1 or path_stat.st_size > MAX_FILE_BYTES:
                raise EvidenceError(f"Unsafe regular file in artifact: {rel}")
            entry.update(type="file", size=path_stat.st_size)
            digest = file_sha256(path)
            files.append({"path": rel, "sha256": digest})
            if is_macho(path):
                architectures = run_tool(["/usr/bin/lipo", "-archs", str(path)]).stdout.split()
                data = path.read_bytes()
                signature, entitlements = signature_evidence(path)
                macho.append(
                    {
                        "path": rel,
                        "architectures": architectures,
                        "installId": macho_install_id(path),
                        "dependencies": macho_dependencies(path),
                        "rpaths": macho_rpaths(path),
                        "embeddedUrls": sorted(
                            {match.decode("utf-8", "strict") for match in URL_RE.findall(data)}
                        ),
                        "signature": signature,
                        "entitlements": entitlements,
                    }
                )
        else:
            raise EvidenceError(f"Unsupported artifact entry type: {rel}")
        inventory.append(entry)

    metadata_path = root / "METADATA.txt"
    provenance_path = root / "SOURCE_PROVENANCE.tsv"
    manifest_path = root / "MANIFEST.txt"
    for required in (metadata_path, provenance_path, manifest_path):
        if not required.is_file() or required.is_symlink():
            raise EvidenceError(f"Artifact evidence file is missing: {required.name}")
    provenance_lines = [
        line
        for line in provenance_path.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    provenance = list(csv.DictReader(provenance_lines, delimiter="\t"))
    return {
        "inventory": inventory,
        "files": files,
        "macho": macho,
        "manifest": manifest_path.read_text(encoding="utf-8").splitlines(),
        "metadata": metadata_path.read_text(encoding="utf-8").splitlines(),
        "provenance": provenance,
    }


def normalized_metadata(lines: list[str]) -> list[str]:
    ignored = ("Qt Version:", "Created:", "Source:", "Source Date Epoch:")
    return ["<expected-version-field>" if line.startswith(ignored) else line for line in lines]


def structural_inventory(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {key: value for key, value in entry.items() if key != "size"}
        for entry in entries
    ]


def compare_evidence(
    left: dict[str, Any],
    right: dict[str, Any],
    left_sha256: str,
    right_sha256: str,
    allow_version_change: bool,
) -> dict[str, Any]:
    differences: list[str] = []
    expected_hash_changes: list[str] = []
    if not allow_version_change:
        if left_sha256 != right_sha256:
            differences.append("archive-digest")
        for field in ("inventory", "files", "macho", "manifest", "metadata", "provenance"):
            if left[field] != right[field]:
                differences.append(field)
    else:
        if structural_inventory(left["inventory"]) != structural_inventory(right["inventory"]):
            differences.append("member-type-mode-symlink-structure")
        if left["macho"] != right["macho"]:
            differences.append("architecture-id-import-rpath-url-entitlement-signature")
        if normalized_metadata(left["metadata"]) != normalized_metadata(right["metadata"]):
            differences.append("metadata-structure")
        left_names = [(row.get("name"), row.get("bottle_tag")) for row in left["provenance"]]
        right_names = [(row.get("name"), row.get("bottle_tag")) for row in right["provenance"]]
        if left_names != right_names:
            differences.append("provenance-name-or-platform-structure")
        left_hashes = {entry["path"]: entry["sha256"] for entry in left["files"]}
        right_hashes = {entry["path"]: entry["sha256"] for entry in right["files"]}
        expected_hash_changes = sorted(
            path
            for path in left_hashes.keys() & right_hashes.keys()
            if left_hashes[path] != right_hashes[path]
        )
    return {
        "result": "match" if not differences else "different",
        "mode": "version-change" if allow_version_change else "exact",
        "archiveSha256": {"left": left_sha256, "right": right_sha256},
        "differences": differences,
        "expectedHashChanges": expected_hash_changes,
        "counts": {
            "leftEntries": len(left["inventory"]),
            "rightEntries": len(right["inventory"]),
            "leftMachO": len(left["macho"]),
            "rightMachO": len(right["macho"]),
        },
    }


def atomic_write(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise EvidenceError(f"Refusing symlink evidence output: {path}")
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=path.parent,
            prefix=f".{path.name}.", delete=False,
        ) as handle:
            temporary = Path(handle.name)
            json.dump(document, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def read_evidence(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() \
        or path.stat().st_size > MAX_OUTPUT_BYTES:
        raise EvidenceError(f"Evidence input must be a bounded regular file: {path}")
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise EvidenceError("Evidence input must contain a JSON object")
    return document


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    subparsers = parser.add_subparsers(dest="command", required=True)
    collect = subparsers.add_parser("collect")
    collect.add_argument("root", type=Path)
    collect.add_argument("--output", required=True, type=Path)
    compare = subparsers.add_parser("compare")
    compare.add_argument("left", type=Path)
    compare.add_argument("right", type=Path)
    compare.add_argument("--left-sha256", required=True)
    compare.add_argument("--right-sha256", required=True)
    compare.add_argument("--allow-version-change", action="store_true")
    compare.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.command == "collect":
            atomic_write(args.output, collect_tree(args.root))
            return 0
        left = read_evidence(args.left)
        right = read_evidence(args.right)
        report = compare_evidence(
            left, right, args.left_sha256, args.right_sha256,
            args.allow_version_change,
        )
        atomic_write(args.output, report)
        return 0 if report["result"] == "match" else 1
    except (EvidenceError, OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
