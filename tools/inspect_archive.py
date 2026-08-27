#!/usr/bin/env python3
"""Inspect a tar.gz archive against bounded WormsWMD safety profiles."""

from __future__ import annotations

import argparse
import dataclasses
import gzip
import hashlib
import os
import re
import stat
import sys
import tarfile
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Dict, Optional, Sequence


MIB = 1024 * 1024
GIB = 1024 * MIB
MAX_METADATA_MEMBER_BYTES = MIB
MAX_PATH_BYTES = 4096
WINDOWS_DRIVE_RE = re.compile(r"^[A-Za-z]:")


class ArchiveInspectionError(ValueError):
    """Raised when an archive violates a resource or layout boundary."""


@dataclass(frozen=True)
class Limits:
    max_compressed_bytes: int
    max_expanded_bytes: int
    max_members: int
    max_member_bytes: int
    max_ratio: float

    def __post_init__(self) -> None:
        values = (
            self.max_compressed_bytes,
            self.max_expanded_bytes,
            self.max_members,
            self.max_member_bytes,
        )
        if any(value <= 0 for value in values) or self.max_ratio <= 0:
            raise ValueError("archive limits must be positive")


@dataclass(frozen=True)
class Profile:
    limits: Limits
    allow_symlinks: bool


@dataclass(frozen=True)
class Summary:
    compressed_bytes: int
    expanded_bytes: int
    stream_bytes: int
    members: int
    regular_files: int
    directories: int
    symlinks: int


PROFILES: Dict[str, Profile] = {
    "qt": Profile(Limits(64 * MIB, 128 * MIB, 1024, 64 * MIB, 200.0), True),
    "kingfisher": Profile(Limits(64 * MIB, 128 * MIB, 32, 128 * MIB, 200.0), False),
    "bottle": Profile(Limits(256 * MIB, GIB, 16_384, 512 * MIB, 200.0), True),
    "save": Profile(Limits(8 * GIB, 8 * GIB, 100_000, 8 * GIB, 10_000.0), False),
}


class BoundedReader:
    """Count expanded bytes and stop before an unbounded gzip stream."""

    def __init__(self, source: BinaryIO, limit: int) -> None:
        self.source = source
        self.limit = limit
        self.count = 0

    def read(self, size: int = -1) -> bytes:
        remaining = self.limit - self.count
        request = remaining + 1 if size < 0 else min(size, remaining + 1)
        data = self.source.read(request)
        self.count += len(data)
        if self.count > self.limit:
            raise ArchiveInspectionError(
                f"expanded tar stream exceeds limit {self.limit} bytes"
            )
        return data


def _stream_limit(limits: Limits) -> int:
    header_budget = min(limits.max_members * 2048, 256 * MIB)
    return limits.max_expanded_bytes + header_budget + 2 * MIB


def _parse_octal_size(field: bytes) -> int:
    if field and field[0] & 0x80:
        raise ArchiveInspectionError("base-256 tar sizes are unsupported")
    candidate = field.rstrip(b"\0 ").lstrip(b" ")
    if not candidate:
        return 0
    if any(byte not in b"01234567" for byte in candidate):
        raise ArchiveInspectionError("tar member has an invalid size field")
    return int(candidate, 8)


def _discard_exact(reader: BoundedReader, size: int) -> None:
    remaining = size
    while remaining:
        chunk = reader.read(min(remaining, MIB))
        if not chunk:
            raise ArchiveInspectionError("truncated tar member payload")
        remaining -= len(chunk)


def _validate_raw_stream(path: Path, limits: Limits, allow_symlinks: bool) -> int:
    stream_limit = _stream_limit(limits)
    raw_members = 0
    zero_blocks = 0
    allowed_types = {b"\0", b"0", b"5", b"x", b"g", b"L", b"K"}
    if allow_symlinks:
        allowed_types.add(b"2")

    try:
        with path.open("rb") as source, gzip.GzipFile(fileobj=source) as expanded:
            reader = BoundedReader(expanded, stream_limit)
            while True:
                header = reader.read(512)
                if not header:
                    break
                if len(header) != 512:
                    raise ArchiveInspectionError("truncated tar header")
                if header == b"\0" * 512:
                    zero_blocks += 1
                    if zero_blocks >= 2:
                        break
                    continue
                if zero_blocks:
                    raise ArchiveInspectionError("tar contains data after an end marker")

                raw_members += 1
                if raw_members > limits.max_members * 3 + 128:
                    raise ArchiveInspectionError("raw tar header count exceeds limit")
                member_size = _parse_octal_size(header[124:136])
                member_type = header[156:157]
                if member_type not in allowed_types:
                    label = {
                        b"1": "hard link",
                        b"2": "symlink",
                        b"3": "character device",
                        b"4": "block device",
                        b"6": "FIFO",
                        b"S": "sparse",
                    }.get(member_type, member_type.decode("ascii", "backslashreplace"))
                    raise ArchiveInspectionError(
                        f"unsupported raw tar {label} member type"
                    )
                if member_type in {b"x", b"g", b"L", b"K"}:
                    if member_size > MAX_METADATA_MEMBER_BYTES:
                        raise ArchiveInspectionError(
                            "tar metadata member exceeds 1 MiB limit"
                        )
                elif member_size > limits.max_member_bytes:
                    raise ArchiveInspectionError(
                        f"tar member size {member_size} exceeds limit "
                        f"{limits.max_member_bytes}"
                    )

                _discard_exact(reader, member_size)
                padding = (-member_size) % 512
                if padding:
                    _discard_exact(reader, padding)

            if zero_blocks < 2:
                raise ArchiveInspectionError("tar is missing its end markers")
            while True:
                trailing = reader.read(MIB)
                if not trailing:
                    break
                if trailing.strip(b"\0"):
                    raise ArchiveInspectionError("tar has nonzero trailing data")
            return reader.count
    except ArchiveInspectionError:
        raise
    except (EOFError, OSError, tarfile.TarError) as error:
        raise ArchiveInspectionError(f"invalid or truncated gzip/tar archive: {error}") from error


def _validate_unicode(value: str, label: str) -> None:
    if not value:
        raise ArchiveInspectionError(f"{label} is empty")
    if len(value.encode("utf-8", "surrogatepass")) > MAX_PATH_BYTES:
        raise ArchiveInspectionError(f"{label} exceeds {MAX_PATH_BYTES} bytes")
    if unicodedata.normalize("NFC", value) != value:
        raise ArchiveInspectionError(f"{label} is not Unicode NFC")
    for character in value:
        if unicodedata.category(character) in {"Cc", "Cf", "Cs"}:
            raise ArchiveInspectionError(f"{label} contains an unsafe Unicode character")


def _canonical_member_path(value: str) -> str:
    _validate_unicode(value, "archive path")
    if value in (".", "./"):
        return "."
    if value.startswith("./"):
        value = value[2:]
    if value.startswith(("/", "//")) or WINDOWS_DRIVE_RE.match(value):
        raise ArchiveInspectionError(f"archive path is absolute: {value!r}")
    if "\\" in value:
        raise ArchiveInspectionError(f"archive path contains a backslash: {value!r}")
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ArchiveInspectionError(f"archive path is noncanonical: {value!r}")
    return "/".join(parts)


def _validate_symlink_target(member_path: str, target: str) -> None:
    _validate_unicode(target, "symlink target")
    if target.startswith(("/", "//")) or WINDOWS_DRIVE_RE.match(target):
        raise ArchiveInspectionError("symlink target is absolute")
    if "\\" in target:
        raise ArchiveInspectionError("symlink target contains a backslash")

    parts = target.split("/")
    if any(part in {"", "."} for part in parts):
        raise ArchiveInspectionError("symlink target is noncanonical")

    resolved = member_path.split("/")[:-1]
    for part in parts:
        if part == "..":
            if not resolved:
                raise ArchiveInspectionError("symlink target escapes archive root")
            resolved.pop()
        else:
            resolved.append(part)


def inspect_archive(
    path: Path, limits: Limits, *, allow_symlinks: bool = False
) -> Summary:
    archive_path = Path(path)
    if archive_path.is_symlink() or not archive_path.is_file():
        raise ArchiveInspectionError(f"archive must be a regular nonlinked file: {path}")
    if archive_path.stat().st_nlink != 1:
        raise ArchiveInspectionError("archive must have link count one")
    compressed_bytes = archive_path.stat().st_size
    if compressed_bytes <= 0:
        raise ArchiveInspectionError("archive is empty")
    if compressed_bytes > limits.max_compressed_bytes:
        raise ArchiveInspectionError(
            f"compressed size {compressed_bytes} exceeds limit "
            f"{limits.max_compressed_bytes}"
        )

    stream_bytes = _validate_raw_stream(archive_path, limits, allow_symlinks)
    members = 0
    regular_files = 0
    directories = 0
    symlinks = 0
    expanded_bytes = 0
    canonical_names: Dict[str, str] = {}

    try:
        with tarfile.open(
            archive_path,
            mode="r|gz",
            encoding="utf-8",
            errors="surrogateescape",
        ) as archive:
            for member in archive:
                members += 1
                if members > limits.max_members:
                    raise ArchiveInspectionError(
                        f"member count {members} exceeds limit {limits.max_members}"
                    )
                canonical = _canonical_member_path(member.name)
                duplicate_key = unicodedata.normalize("NFC", canonical).casefold()
                if duplicate_key in canonical_names:
                    label = (
                        "duplicate"
                        if canonical_names[duplicate_key] == canonical
                        else "canonical duplicate"
                    )
                    raise ArchiveInspectionError(f"archive contains a {label}: {canonical}")
                canonical_names[duplicate_key] = canonical

                if canonical == "." and not member.isdir():
                    raise ArchiveInspectionError(
                        "archive root marker must be a directory"
                    )

                if getattr(member, "sparse", None) is not None \
                    or member.type == tarfile.GNUTYPE_SPARSE:
                    raise ArchiveInspectionError("sparse archive members are unsupported")
                if member.mode & 0o7000:
                    raise ArchiveInspectionError(
                        f"archive member has unsafe permission mode: {canonical}"
                    )
                if member.uid < 0 or member.gid < 0:
                    raise ArchiveInspectionError("archive member has a negative owner ID")

                if member.isreg():
                    regular_files += 1
                    if member.size > limits.max_member_bytes:
                        raise ArchiveInspectionError(
                            f"member size {member.size} exceeds limit "
                            f"{limits.max_member_bytes}: {canonical}"
                        )
                    expanded_bytes += member.size
                    if expanded_bytes > limits.max_expanded_bytes:
                        raise ArchiveInspectionError(
                            f"expanded size {expanded_bytes} exceeds limit "
                            f"{limits.max_expanded_bytes}"
                        )
                    ratio = expanded_bytes / compressed_bytes
                    if ratio > limits.max_ratio:
                        raise ArchiveInspectionError(
                            f"compression ratio {ratio:.2f}:1 exceeds limit "
                            f"{limits.max_ratio:.2f}:1"
                        )
                elif member.isdir():
                    directories += 1
                elif member.issym():
                    if not allow_symlinks:
                        raise ArchiveInspectionError("symlink archive members are unsupported")
                    _validate_symlink_target(canonical, member.linkname)
                    symlinks += 1
                elif member.islnk():
                    raise ArchiveInspectionError("hard link archive members are unsupported")
                else:
                    raise ArchiveInspectionError(
                        f"unsupported archive member type: {canonical}"
                    )
    except ArchiveInspectionError:
        raise
    except (EOFError, OSError, tarfile.TarError, UnicodeError) as error:
        raise ArchiveInspectionError(f"invalid or truncated gzip/tar archive: {error}") from error

    if members == 0:
        raise ArchiveInspectionError("archive contains no members")
    return Summary(
        compressed_bytes=compressed_bytes,
        expanded_bytes=expanded_bytes,
        stream_bytes=stream_bytes,
        members=members,
        regular_files=regular_files,
        directories=directories,
        symlinks=symlinks,
    )


def copy_archive_for_inspection(
    source: Path,
    destination: Path,
    max_compressed_bytes: int,
    expected_sha256: Optional[str] = None,
) -> Path:
    source_path = Path(source)
    destination_path = Path(destination)
    if expected_sha256 is not None and not re.fullmatch(
        r"[0-9a-fA-F]{64}", expected_sha256
    ):
        raise ArchiveInspectionError("expected SHA-256 is invalid")
    if destination_path.exists() or destination_path.is_symlink():
        raise ArchiveInspectionError(
            f"refusing to overwrite archive copy: {destination_path}"
        )

    source_flags = os.O_RDONLY
    destination_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        source_flags |= os.O_NOFOLLOW
        destination_flags |= os.O_NOFOLLOW
    source_fd = -1
    destination_fd = -1
    destination_created = False
    completed = False
    digest = hashlib.sha256()
    copied_bytes = 0
    try:
        source_fd = os.open(str(source_path), source_flags)
        source_stat = os.fstat(source_fd)
        if not stat.S_ISREG(source_stat.st_mode):
            raise ArchiveInspectionError(
                f"archive source must be a regular nonlinked file: {source_path}"
            )
        if source_stat.st_size <= 0:
            raise ArchiveInspectionError("archive is empty")
        if source_stat.st_size > max_compressed_bytes:
            raise ArchiveInspectionError(
                f"compressed size {source_stat.st_size} exceeds limit "
                f"{max_compressed_bytes}"
            )

        destination_fd = os.open(
            str(destination_path), destination_flags, 0o600
        )
        destination_created = True
        with os.fdopen(source_fd, "rb", closefd=True) as source_file:
            source_fd = -1
            with os.fdopen(destination_fd, "wb", closefd=True) as destination_file:
                destination_fd = -1
                while True:
                    remaining = max_compressed_bytes - copied_bytes
                    chunk = source_file.read(min(MIB, remaining + 1))
                    if not chunk:
                        break
                    copied_bytes += len(chunk)
                    if copied_bytes > max_compressed_bytes:
                        raise ArchiveInspectionError(
                            f"compressed copy exceeds limit {max_compressed_bytes} bytes"
                        )
                    digest.update(chunk)
                    destination_file.write(chunk)
                destination_file.flush()
                os.fsync(destination_file.fileno())

        if copied_bytes <= 0:
            raise ArchiveInspectionError("archive is empty")
        if expected_sha256 is not None and digest.hexdigest() != expected_sha256.lower():
            raise ArchiveInspectionError(
                "temporary archive copy failed SHA-256 verification"
            )
        completed = True
        return destination_path
    except OSError as error:
        raise ArchiveInspectionError(f"could not create bounded archive copy: {error}") from error
    finally:
        if source_fd >= 0:
            os.close(source_fd)
        if destination_fd >= 0:
            os.close(destination_fd)
        if destination_created and not completed:
            try:
                destination_path.unlink()
            except FileNotFoundError:
                pass


def copy_and_inspect_archive(
    source: Path,
    destination: Path,
    limits: Limits,
    *,
    allow_symlinks: bool = False,
    expected_sha256: Optional[str] = None,
) -> Summary:
    copied = copy_archive_for_inspection(
        source,
        destination,
        limits.max_compressed_bytes,
        expected_sha256,
    )
    try:
        return inspect_archive(copied, limits, allow_symlinks=allow_symlinks)
    except Exception:
        try:
            copied.unlink()
        except FileNotFoundError:
            pass
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Inspect a tar.gz archive without extracting it."
    )
    parser.add_argument("--profile", required=True, choices=sorted(PROFILES))
    parser.add_argument(
        "--max-expanded-bytes",
        type=int,
        help="Override expanded limit for the save profile only (maximum 8 GiB)",
    )
    parser.add_argument(
        "--copy-to",
        type=Path,
        help="Create and inspect an exclusive owner-only bounded copy",
    )
    parser.add_argument(
        "--expected-sha256",
        help="Require this SHA-256 for the completed --copy-to file",
    )
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("archive", type=Path)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    profile = PROFILES[args.profile]
    limits = profile.limits
    if args.max_expanded_bytes is not None:
        if args.profile != "save":
            parser.error("--max-expanded-bytes is available only for the save profile")
        if not 0 < args.max_expanded_bytes <= 8 * GIB:
            parser.error("--max-expanded-bytes must be between 1 and 8 GiB")
        limits = dataclasses.replace(
            limits,
            max_expanded_bytes=args.max_expanded_bytes,
            max_member_bytes=args.max_expanded_bytes,
        )
    if args.expected_sha256 is not None and args.copy_to is None:
        parser.error("--expected-sha256 requires --copy-to")

    try:
        if args.copy_to is None:
            summary = inspect_archive(
                args.archive,
                limits,
                allow_symlinks=profile.allow_symlinks,
            )
        else:
            summary = copy_and_inspect_archive(
                args.archive,
                args.copy_to,
                limits,
                allow_symlinks=profile.allow_symlinks,
                expected_sha256=args.expected_sha256,
            )
    except ArchiveInspectionError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if not args.quiet:
        ratio = summary.expanded_bytes / summary.compressed_bytes
        print(
            f"archive-ok profile={args.profile} compressed={summary.compressed_bytes} "
            f"expanded={summary.expanded_bytes} stream={summary.stream_bytes} "
            f"members={summary.members} regular={summary.regular_files} "
            f"directories={summary.directories} symlinks={summary.symlinks} "
            f"ratio={ratio:.2f}:1"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
