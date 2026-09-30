#!/usr/bin/env python3
"""Fail-closed preflight checks for the V16 image repack."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
from typing import Any
import xml.etree.ElementTree as ET

REQUIRED_TOOLS = (
    "lpdump", "lpunpack", "lpmake", "simg2img", "img2simg", "avbtool",
    "file", "sha256sum", "e2fsck", "resize2fs", "mount", "umount",
    "rsync", "getfattr", "setfattr", "readelf",
)
SPARSE_MAGIC = 0xED26FF3A


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_hashes(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(maxsplit=1)
        if len(fields) != 2 or len(fields[0]) != 64:
            raise ValueError(f"{path}:{number}: expected '<sha256>  <path>'")
        values[fields[1].lstrip("*")] = fields[0].lower()
    return values


def apk_certificate(path: Path) -> str | None:
    tool = shutil.which("apksigner")
    if not tool or not path.is_file():
        return None
    proc = subprocess.run(
        [tool, "verify", "--print-certs", str(path)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    return proc.stdout.strip() if proc.returncode == 0 else f"INVALID: {proc.stdout.strip()}"


def resolve(root: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config/v16.json")
    parser.add_argument("--json-report")
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    root = config_path.parent.parent
    config: dict[str, Any] = json.loads(config_path.read_text())
    paths = config["paths"]
    errors: list[str] = []
    warnings: list[str] = []

    tools = {name: shutil.which(name) for name in REQUIRED_TOOLS}
    for name, location in tools.items():
        if not location:
            errors.append(f"missing required host tool: {name}")
    if not (shutil.which("apkanalyzer") or shutil.which("aapt2")):
        warnings.append("neither apkanalyzer nor aapt2 is installed; APK dependency audit is limited")
    if not shutil.which("apksigner"):
        warnings.append("apksigner is absent; signer certificate reports will not be generated")

    stock = resolve(root, paths["stock_super"])
    manifest = resolve(root, paths["flash_manifest"])
    if not stock.is_file():
        errors.append(f"missing full stock super image: {stock}")
    if not manifest.is_dir() or not any(manifest.iterdir()):
        errors.append(f"missing/non-populated Lenovo flash manifest directory: {manifest}")

    apk_files: list[Path] = []
    for key in ("gmscore", "fakestore", "aurora_store"):
        item = resolve(root, paths[key])
        apk_files.append(item)
        if not item.is_file():
            errors.append(f"missing APK '{key}': {item}")
    miui = root / "inputs/hyperos/MiuiHome.apk"
    apk_files.append(miui)
    if not miui.is_file():
        errors.append(f"missing donor launcher: {miui}")
    permissions = resolve(root, paths["microg_permissions"])
    if not permissions.is_file():
        errors.append(f"missing reviewed microG privileged-permission allowlist: {permissions}")
    else:
        try:
            document = ET.parse(permissions)
            packages = {node.get("package") for node in document.findall(".//privapp-permissions")}
            if "com.google.android.gms" not in packages:
                errors.append("microG permissions XML has no com.google.android.gms privapp-permissions entry")
        except ET.ParseError as exc:
            errors.append(f"invalid microG permissions XML: {exc}")
    input_files = apk_files + [permissions]

    hashes_path = root / "config/inputs.sha256"
    try:
        expected = load_hashes(hashes_path)
    except ValueError as exc:
        errors.append(str(exc))
        expected = {}
    observed: dict[str, str] = {}
    for item in ([stock] if stock.is_file() else []) + [p for p in input_files if p.is_file()]:
        relative = os.path.relpath(item, root)
        observed[relative] = sha256(item)
        wanted = expected.get(relative)
        if not wanted:
            errors.append(f"no pinned SHA-256 for {relative} in {hashes_path}")
        elif wanted != observed[relative]:
            errors.append(f"SHA-256 mismatch for {relative}")

    image_format = None
    if stock.is_file():
        with stock.open("rb") as stream:
            magic_data = stream.read(4)
        if len(magic_data) == 4 and struct.unpack("<I", magic_data)[0] == SPARSE_MAGIC:
            image_format = "android-sparse"
        else:
            image_format = "raw-or-unknown"

    if config["device"].get("required_bootloader_state") != "unlocked":
        errors.append("configuration must explicitly require an unlocked bootloader")
    warnings.extend([
        "signature spoofing is not enabled by APK placement; framework capability must be proven",
        "MiuiHome is experimental until framework/native dependency and signer checks pass",
        "no OEM-equivalent AVB signing can occur without Lenovo private keys",
    ])

    report = {
        "ok": not errors,
        "config": str(config_path),
        "stock_image_format": image_format,
        "tools": tools,
        "sha256": observed,
        "errors": errors,
        "warnings": warnings,
        "apk_certificates": {
            os.path.relpath(path, root): apk_certificate(path)
            for path in apk_files if path.is_file()
        },
    }
    print(json.dumps(report, indent=2))
    if args.json_report:
        destination = Path(args.json_report)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["ok"] else 2


if __name__ == "__main__":
    sys.exit(main())
