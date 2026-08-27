#!/usr/bin/env python3
"""Verify a WormsWMD release ZIP and its complete manifest without extraction."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import stat
import sys
import unicodedata
import zipfile
from collections.abc import Sequence
from pathlib import Path, PurePosixPath
from typing import Any

MAX_ZIP_BYTES = 512 * 1024 * 1024
MAX_EXPANDED_BYTES = 1024 * 1024 * 1024
MAX_MEMBER_BYTES = 256 * 1024 * 1024
MAX_MEMBERS = 20_000
MAX_RATIO = 1_000
MAX_MANIFEST_BYTES = 16 * 1024 * 1024
HASH_RE = re.compile(r"^[0-9a-f]{64}$")


class ReleaseZipError(ValueError):
    """Raised when release ZIP structure or manifest evidence is unsafe."""


def canonical_alias(path: str) -> str:
    return unicodedata.normalize("NFC", path).casefold()


def safe_member_name(name: str) -> str:
    if not name or "\\" in name or any(ord(char) < 32 or ord(char) == 127 for char in name):
        raise ReleaseZipError("Release ZIP contains an unsafe member name")
    pure = PurePosixPath(name)
    if pure.is_absolute() or any(part in {"", ".", ".."} for part in pure.parts):
        raise ReleaseZipError(f"Release ZIP member escapes its root: {name}")
    return pure.as_posix().rstrip("/")


def zip_entry_type(info: zipfile.ZipInfo) -> str:
    if info.is_dir():
        return "directory"
    mode = (info.external_attr >> 16) & 0xFFFF
    if mode == 0 or stat.S_ISREG(mode):
        return "file"
    if stat.S_ISLNK(mode):
        raise ReleaseZipError(f"Release ZIP contains a symbolic link: {info.filename}")
    raise ReleaseZipError(f"Unsupported release ZIP entry type: {info.filename}")


def safe_permissions(mode: int, label: str) -> int:
    permissions = stat.S_IMODE(mode)
    if permissions & 0o7022:
        raise ReleaseZipError(f"Release entry has unsafe permissions: {label}")
    return permissions


def parse_manifest(data: bytes) -> dict[str, tuple[str, int]]:
    if len(data) > MAX_MANIFEST_BYTES:
        raise ReleaseZipError("Release manifest exceeds its size limit")
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise ReleaseZipError("Release manifest is not UTF-8") from error
    if not lines or lines[0] != "# WormsWMD manifest v2":
        raise ReleaseZipError("Release manifest must use version 2")
    expected: dict[str, tuple[str, int]] = {}
    aliases: set[str] = set()
    for line in lines:
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 3 or not HASH_RE.fullmatch(fields[0]) \
            or not fields[1].isdigit():
            raise ReleaseZipError("Release manifest contains a malformed row")
        rel = safe_member_name(fields[2])
        alias = canonical_alias(rel)
        if rel in expected or alias in aliases:
            raise ReleaseZipError(f"Release manifest has a duplicate path: {rel}")
        aliases.add(alias)
        expected[rel] = (fields[0], int(fields[1]))
    if not expected:
        raise ReleaseZipError("Release manifest contains no entries")
    return expected


def digest_zip_member(
    archive: zipfile.ZipFile, info: zipfile.ZipInfo, max_bytes: int
) -> tuple[str, int]:
    digest = hashlib.sha256()
    total = 0
    with archive.open(info, "r") as source:
        while True:
            chunk = source.read(min(1024 * 1024, max_bytes + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ReleaseZipError(f"Release ZIP member exceeds limit: {info.filename}")
            digest.update(chunk)
    return digest.hexdigest(), total


def expected_tree_files(root: Path) -> dict[str, tuple[str, int, int]]:
    root_stat = root.lstat()
    if not stat.S_ISDIR(root_stat.st_mode) or root.is_symlink():
        raise ReleaseZipError(f"Expected release tree must be a directory: {root}")
    expected: dict[str, tuple[str, int, int]] = {}
    for directory, names, filenames in os.walk(root, followlinks=False):
        directory_path = Path(directory)
        safe_permissions(directory_path.lstat().st_mode, str(directory_path))
        for name in names:
            child = directory_path / name
            child_stat = child.lstat()
            if not stat.S_ISDIR(child_stat.st_mode) or child.is_symlink():
                raise ReleaseZipError(f"Expected release tree has unsafe entry: {child}")
        for name in filenames:
            child = directory_path / name
            child_stat = child.lstat()
            if not stat.S_ISREG(child_stat.st_mode) or child.is_symlink() \
                or child_stat.st_nlink != 1:
                raise ReleaseZipError(f"Expected release tree has unsafe file: {child}")
            rel = child.relative_to(root).as_posix()
            expected[rel] = (
                file_sha256(child),
                child_stat.st_size,
                safe_permissions(child_stat.st_mode, str(child)),
            )
    return expected


def verify_release_zip(
    path: Path, expected_tree: Path | None = None
) -> dict[str, Any]:
    path_stat = path.lstat()
    if not stat.S_ISREG(path_stat.st_mode) or path.is_symlink() \
        or path_stat.st_nlink != 1 or path_stat.st_size > MAX_ZIP_BYTES:
        raise ReleaseZipError(f"Release ZIP must be a bounded regular file: {path}")
    try:
        archive = zipfile.ZipFile(path, "r")
    except zipfile.BadZipFile as error:
        raise ReleaseZipError("Release ZIP is invalid") from error
    with archive:
        if archive.comment:
            raise ReleaseZipError("Release ZIP comments are unsupported")
        infos = archive.infolist()
        if not infos or len(infos) > MAX_MEMBERS:
            raise ReleaseZipError("Release ZIP has an invalid member count")
        expanded = sum(info.file_size for info in infos)
        if expanded > MAX_EXPANDED_BYTES:
            raise ReleaseZipError("Release ZIP exceeds its expanded size limit")
        names: dict[str, zipfile.ZipInfo] = {}
        aliases: set[str] = set()
        roots: set[str] = set()
        entry_types: dict[str, str] = {}
        for info in infos:
            if info.comment or info.extra:
                raise ReleaseZipError(
                    f"Release ZIP entry has unverified metadata: {info.filename}"
                )
            if info.is_dir() and (info.file_size or info.compress_size):
                raise ReleaseZipError(
                    f"Release ZIP directory contains hidden data: {info.filename}"
                )
            if info.flag_bits & 0x1:
                raise ReleaseZipError("Encrypted release ZIP members are unsupported")
            if info.file_size > MAX_MEMBER_BYTES:
                raise ReleaseZipError(f"Release ZIP member is too large: {info.filename}")
            if info.compress_size > 0 \
                and info.file_size > info.compress_size * MAX_RATIO:
                raise ReleaseZipError(f"Release ZIP member ratio is unsafe: {info.filename}")
            name = safe_member_name(info.filename)
            alias = canonical_alias(name)
            if name in names or alias in aliases:
                raise ReleaseZipError(f"Release ZIP has a duplicate path: {name}")
            names[name] = info
            aliases.add(alias)
            roots.add(PurePosixPath(name).parts[0])
            entry_types[name] = zip_entry_type(info)
            raw_mode = (info.external_attr >> 16) & 0xFFFF
            if raw_mode:
                safe_permissions(raw_mode, info.filename)
        if len(roots) != 1:
            raise ReleaseZipError("Release ZIP must contain exactly one root directory")
        root = roots.pop()
        if not root.startswith("WormsWMD-macOS-Fix-") \
            or entry_types.get(root) != "directory":
            raise ReleaseZipError("Release ZIP root is invalid")
        if path.suffix != ".zip" or path.stem != root:
            raise ReleaseZipError("Release ZIP filename and root must match")
        manifest_name = f"{root}/RELEASE_MANIFEST.tsv"
        manifest_info = names.get(manifest_name)
        if manifest_info is None or entry_types[manifest_name] != "file":
            raise ReleaseZipError("Release ZIP is missing its regular manifest")
        manifest_hash, manifest_size = digest_zip_member(
            archive, manifest_info, MAX_MANIFEST_BYTES
        )
        with archive.open(manifest_info, "r") as source:
            manifest_bytes = source.read(MAX_MANIFEST_BYTES + 1)
        expected = parse_manifest(manifest_bytes)

        actual = {
            name[len(root) + 1:]: (info, entry_types[name])
            for name, info in names.items()
            if name != root and name != manifest_name \
            and entry_types[name] != "directory"
        }
        if set(actual) != set(expected):
            missing = sorted(set(expected) - set(actual))
            extra = sorted(set(actual) - set(expected))
            raise ReleaseZipError(
                f"Release manifest membership differs (missing={missing}, extra={extra})"
            )
        verified: dict[str, tuple[str, int, int]] = {}
        for rel, (expected_hash, expected_size) in expected.items():
            info, entry_type = actual[rel]
            if entry_type != "file":
                raise ReleaseZipError(f"Manifest names unsupported entry: {rel}")
            actual_hash, actual_size = digest_zip_member(
                archive, info, MAX_MEMBER_BYTES
            )
            if actual_hash != expected_hash or actual_size != expected_size:
                raise ReleaseZipError(f"Release manifest mismatch: {rel}")
            raw_mode = (info.external_attr >> 16) & 0xFFFF
            verified[rel] = (actual_hash, actual_size, stat.S_IMODE(raw_mode))

        if expected_tree is not None:
            if expected_tree.name != root:
                raise ReleaseZipError("Expected release tree and ZIP root differ")
            expected_files = expected_tree_files(expected_tree)
            expected_manifest = expected_files.pop("RELEASE_MANIFEST.tsv", None)
            if expected_manifest is None:
                raise ReleaseZipError("Expected release tree is missing its manifest")
            if set(verified) != set(expected_files):
                missing = sorted(set(expected_files) - set(verified))
                extra = sorted(set(verified) - set(expected_files))
                raise ReleaseZipError(
                    "Release ZIP differs from expected source tree "
                    f"(missing={missing}, extra={extra})"
                )
            if verified != expected_files:
                differing = sorted(
                    rel for rel in verified if verified[rel] != expected_files[rel]
                )
                raise ReleaseZipError(
                    f"Release ZIP content or mode differs from source: {differing}"
                )
            manifest_mode = stat.S_IMODE(
                (manifest_info.external_attr >> 16) & 0xFFFF
            )
            if (manifest_hash, manifest_size, manifest_mode) != expected_manifest:
                raise ReleaseZipError("Release ZIP manifest differs from source build")
    return {"root": root, "entries": len(expected), "sha256": file_sha256(path)}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("archive", type=Path)
    parser.add_argument(
        "--expected-tree",
        type=Path,
        help="Require every packaged file and mode to match this rebuilt tree",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        result = verify_release_zip(args.archive, args.expected_tree)
    except (OSError, ReleaseZipError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        f"Release ZIP verified: {result['root']} "
        f"({result['entries']} entries, sha256={result['sha256']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
