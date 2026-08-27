#!/usr/bin/env python3
"""Validate Qt component scope, scanner identity, VEX, and Grype evidence."""

from __future__ import annotations

import csv
import fnmatch
import json
import re
from datetime import date, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

POLICY_HEADER = [
    "name",
    "supplier",
    "scope",
    "shipped_file_evidence",
    "purl_template",
    "cpe_product",
    "identity_source",
    "rationale",
    "review_date",
    "owner",
]
VEX_HEADER = [
    "advisory_id",
    "component",
    "state",
    "rationale",
    "owner",
    "review_date",
    "expires",
]
NAME_RE = re.compile(r"^[A-Za-z0-9@+_.\-/]+$")
CPE_PRODUCT_RE = re.compile(r"^[a-z0-9_.-]+:[a-z0-9_.-]+$")
ADVISORY_RE = re.compile(
    r"^(?:CVE-[0-9]{4}-[0-9]{4,}|"
    r"GHSA-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4}-"
    r"[23456789cfghjmpqrvwx]{4})$"
)
MAX_COMPONENTS = 1_000
MAX_POLICY_BYTES = 1_048_576
MAX_VEX_BYTES = 1_048_576
MAX_SCAN_REPORT_BYTES = 32 * 1024 * 1024
MAX_VEX_REVIEW_AGE = timedelta(days=90)


class QtPolicyError(ValueError):
    """Raised when Qt scope, scanner, or VEX evidence is not trustworthy."""


def read_bounded_file(path: Path, max_bytes: int, label: str) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise QtPolicyError(f"{label} must be a regular file: {path}")
    with path.open("rb") as source:
        data = source.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise QtPolicyError(f"{label} exceeds the size limit")
    return data


def parse_date(value: str, label: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise QtPolicyError(f"Invalid {label}: expected YYYY-MM-DD") from error


def read_component_policy(path: Path) -> list[dict[str, str]]:
    policy = read_bounded_file(path, MAX_POLICY_BYTES, "Component policy")
    lines = [
        line
        for line in policy.decode("utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    if not lines:
        raise QtPolicyError("Component policy is empty")
    reader = csv.DictReader(lines, delimiter="\t")
    if reader.fieldnames != POLICY_HEADER:
        raise QtPolicyError(
            "Component policy header does not match the supported schema"
        )

    rows: list[dict[str, str]] = []
    names: set[str] = set()
    for raw_row in reader:
        if len(rows) >= MAX_COMPONENTS:
            raise QtPolicyError("Component policy exceeds the component limit")
        if None in raw_row or any(value is None for value in raw_row.values()):
            raise QtPolicyError("Malformed component policy row")
        row = {key: value.strip() for key, value in raw_row.items()}
        if any(not row[field] for field in POLICY_HEADER):
            raise QtPolicyError("Component policy rows may not contain empty fields")
        name = row["name"]
        if not NAME_RE.fullmatch(name) or name in names:
            raise QtPolicyError(
                f"Invalid or duplicate component policy name: {name}"
            )
        names.add(name)
        if row["scope"] not in {"runtime", "build"}:
            raise QtPolicyError(f"Invalid component scope for {name}")
        template_remainder = row["purl_template"].replace("{version}", "")
        if row["purl_template"].count("{version}") != 1 \
            or not row["purl_template"].startswith("pkg:") \
            or "{" in template_remainder \
            or "}" in template_remainder:
            raise QtPolicyError(f"Invalid version-neutral purl template for {name}")
        if row["cpe_product"] != "unmapped" \
            and not CPE_PRODUCT_RE.fullmatch(row["cpe_product"]):
            raise QtPolicyError(f"Invalid CPE product mapping for {name}")
        identity_url = urlparse(row["identity_source"])
        if identity_url.scheme != "https" or not identity_url.hostname:
            raise QtPolicyError(f"Identity source must use HTTPS for {name}")
        parse_date(row["review_date"], f"review date for {name}")
        evidence = row["shipped_file_evidence"].split(";")
        if any(
            not item
            or item.startswith("/")
            or item in {".", ".."}
            or "/../" in f"/{item}/"
            or any(ord(char) < 32 for char in item)
            for item in evidence
        ):
            raise QtPolicyError(f"Invalid shipped-file evidence for {name}")
        if row["scope"] == "runtime" and any(
            item == "-" or item.startswith("!") for item in evidence
        ):
            raise QtPolicyError(f"Runtime component has no positive evidence: {name}")
        if row["scope"] == "build" and any(
            not item.startswith("!") for item in evidence
        ):
            raise QtPolicyError(
                f"Build-only component needs negative evidence: {name}"
            )
        rows.append(row)
    if not rows:
        raise QtPolicyError("Component policy contains no components")
    return sorted(rows, key=lambda item: item["name"])


def validate_component_policy(
    policy_rows: list[dict[str, str]],
    provenance_rows: list[dict[str, str]],
    archive_members: set[str],
) -> list[dict[str, str]]:
    policy_names = {row["name"] for row in policy_rows}
    provenance_names = {row["name"] for row in provenance_rows}
    if policy_names != provenance_names:
        missing = sorted(provenance_names - policy_names)
        extra = sorted(policy_names - provenance_names)
        raise QtPolicyError(
            "Component policy and provenance names differ "
            f"(missing={missing}, extra={extra})"
        )
    runtime_count = 0
    for row in policy_rows:
        if row["scope"] not in {"runtime", "build"}:
            raise QtPolicyError(f"Invalid component scope for {row['name']}")
        if row["cpe_product"] != "unmapped" \
            and not CPE_PRODUCT_RE.fullmatch(row["cpe_product"]):
            raise QtPolicyError(
                f"Invalid CPE product mapping for {row['name']}"
            )
        evidence = row["shipped_file_evidence"].split(";")
        if row["scope"] == "runtime":
            runtime_count += 1
            for pattern in evidence:
                if not any(
                    fnmatch.fnmatchcase(member, pattern)
                    for member in archive_members
                ):
                    raise QtPolicyError(
                        f"Runtime evidence is not shipped for {row['name']}: {pattern}"
                    )
        else:
            for negative_pattern in evidence:
                pattern = negative_pattern[1:]
                if any(
                    fnmatch.fnmatchcase(member, pattern)
                    for member in archive_members
                ):
                    raise QtPolicyError(
                        f"Build-only component became reachable: {row['name']}"
                    )
    if runtime_count == 0:
        raise QtPolicyError("Component policy has zero runtime coverage")
    return sorted(policy_rows, key=lambda item: item["name"])


def read_vex(path: Path, as_of: date) -> list[dict[str, str]]:
    vex = read_bounded_file(path, MAX_VEX_BYTES, "VEX policy")
    lines = [
        line
        for line in vex.decode("utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    if not lines:
        raise QtPolicyError("VEX policy is empty")
    reader = csv.DictReader(lines, delimiter="\t")
    if reader.fieldnames != VEX_HEADER:
        raise QtPolicyError("VEX policy header does not match the supported schema")
    rows: list[dict[str, str]] = []
    identities: set[tuple[str, str]] = set()
    allowed_states = {"affected", "fixed", "in_triage", "not_affected"}
    for raw_row in reader:
        if None in raw_row or any(value is None for value in raw_row.values()):
            raise QtPolicyError("Malformed VEX policy row")
        row = {key: value.strip() for key, value in raw_row.items()}
        if any(not row[field] for field in VEX_HEADER):
            raise QtPolicyError("VEX policy rows may not contain empty fields")
        identity = (row["advisory_id"], row["component"])
        if not ADVISORY_RE.fullmatch(row["advisory_id"]) or identity in identities:
            raise QtPolicyError("Invalid or duplicate VEX advisory")
        identities.add(identity)
        if row["state"] not in allowed_states:
            raise QtPolicyError(f"Invalid VEX state for {row['advisory_id']}")
        reviewed = parse_date(row["review_date"], "VEX review date")
        expires = parse_date(row["expires"], "VEX expiry")
        if reviewed > as_of or as_of - reviewed > MAX_VEX_REVIEW_AGE:
            raise QtPolicyError(f"Stale VEX review for {row['advisory_id']}")
        if expires < as_of or expires < reviewed:
            raise QtPolicyError(f"Expired VEX entry for {row['advisory_id']}")
        rows.append(row)
    if not rows:
        raise QtPolicyError("VEX policy contains no advisories")
    return sorted(rows, key=lambda item: (item["advisory_id"], item["component"]))


def read_json_document(path: Path, max_bytes: int, label: str) -> dict[str, Any]:
    data = read_bounded_file(path, max_bytes, label)
    try:
        document = json.loads(data.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise QtPolicyError(f"Invalid {label} JSON") from error
    if not isinstance(document, dict):
        raise QtPolicyError(f"Invalid {label}: expected an object")
    return document


def normalize_grype_report(
    sbom_path: Path,
    grype_report_path: Path,
    as_of: date,
    vex_path: Path | None = None,
) -> dict[str, Any]:
    sbom = read_json_document(sbom_path, MAX_SCAN_REPORT_BYTES, "Qt SBOM")
    report = read_json_document(
        grype_report_path, MAX_SCAN_REPORT_BYTES, "Grype report"
    )
    components = sbom.get("components")
    if not isinstance(components, list):
        raise QtPolicyError("Qt SBOM components must be an array")
    runtime_components = [
        component
        for component in components
        if isinstance(component, dict) and component.get("scope") == "required"
    ]
    if not runtime_components:
        raise QtPolicyError("Scanner parsed zero runtime inventory")
    if any(not isinstance(component.get("name"), str) for component in runtime_components):
        raise QtPolicyError("Runtime component is missing its name")
    runtime_names = {component["name"] for component in runtime_components}
    unmapped = sorted(
        component["name"]
        for component in runtime_components
        if not component.get("cpe")
    )
    matches = report.get("matches")
    descriptor = report.get("descriptor")
    source = report.get("source")
    if not isinstance(matches, list) \
        or not isinstance(descriptor, dict) \
        or not isinstance(source, dict):
        raise QtPolicyError("Grype report is missing required result fields")

    vex_rows: list[dict[str, str]] = []
    if vex_path is not None:
        vex_rows = read_vex(vex_path, as_of)
        unknown_components = sorted(
            {row["component"] for row in vex_rows} - runtime_names
        )
        if unknown_components:
            raise QtPolicyError(
                f"VEX references unknown runtime components: {unknown_components}"
            )
    vex_by_match = {
        (row["advisory_id"], row["component"]): row for row in vex_rows
    }
    for match in matches:
        if not isinstance(match, dict):
            raise QtPolicyError("Grype report contains a malformed match")
        artifact = match.get("artifact")
        vulnerability = match.get("vulnerability")
        if not isinstance(artifact, dict) or not isinstance(vulnerability, dict):
            raise QtPolicyError(
                "Grype report match lacks artifact or vulnerability"
            )
        vex = vex_by_match.get((vulnerability.get("id"), artifact.get("name")))
        if vex is not None:
            match["wormswmdVex"] = vex
    matches.sort(
        key=lambda match: (
            str(match["artifact"].get("name", "")),
            str(match["artifact"].get("version", "")),
            str(match["vulnerability"].get("id", "")),
        )
    )
    timestamp = sbom.get("metadata", {}).get("timestamp")
    if not isinstance(timestamp, str):
        raise QtPolicyError("Qt SBOM metadata timestamp is missing")
    descriptor["timestamp"] = timestamp
    source["target"] = sbom_path.name
    report["wormswmd"] = {
        "mode": "report-only",
        "runtimeInventoryCount": len(runtime_components),
        "unmappedRuntimeComponents": unmapped,
        "vexEntryCount": len(vex_rows),
    }
    return report
