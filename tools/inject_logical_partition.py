#!/usr/bin/env python3
"""Inject a smaller filesystem image into selected logical-super partitions.

The input super image must already be a *raw* dynamic-partition image.  This
program changes only the physical extents belonging to the requested logical
partitions; it never rewrites LP metadata.  It is intended for creating a
Lenovo-vendor / Xiaomi-HyperOS hybrid where the supplied HyperOS system image
fits within each original Lenovo ``system_[ab]`` logical partition.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import shutil
import sys
from pathlib import Path

SECTOR_SIZE = 512
LINEAR_TARGET = 0


def load_lpunpack(path: Path):
    spec = importlib.util.spec_from_file_location("injection_lpunpack", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load lpunpack module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_metadata(lpmod, super_path: Path):
    unpacker = lpmod.LpUnpack(SUPER_IMAGE=str(super_path), OUTPUT_DIR=Path("."))
    try:
        return unpacker._read_metadata()
    finally:
        unpacker._fd.close()


def extents_for(metadata, name: str):
    partition = next((part for part in metadata.partitions if part.name == name), None)
    if partition is None:
        available = ", ".join(part.name for part in metadata.partitions)
        raise RuntimeError(f"logical partition {name!r} not found; available: {available}")
    selected = []
    for offset in range(partition.num_extents):
        extent = metadata.extents[partition.first_extent_index + offset]
        if extent.target_type != LINEAR_TARGET:
            raise RuntimeError(f"{name} uses unsupported extent target type {extent.target_type}")
        selected.append((extent.target_data * SECTOR_SIZE, extent.num_sectors * SECTOR_SIZE))
    return selected


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def hash_prefix(fd, extents, amount: int) -> str:
    digest = hashlib.sha256()
    remaining = amount
    for offset, size in extents:
        if not remaining:
            break
        take = min(size, remaining)
        fd.seek(offset)
        while take:
            block = fd.read(min(take, 4 * 1024 * 1024))
            if not block:
                raise RuntimeError("unexpected EOF while verifying logical partition")
            digest.update(block)
            take -= len(block)
            remaining -= len(block)
    if remaining:
        raise RuntimeError("logical partition is shorter than injected image")
    return digest.hexdigest()


def inject(fd, extents, source: Path) -> tuple[int, int]:
    source_size = source.stat().st_size
    capacity = sum(size for _, size in extents)
    if source_size > capacity:
        raise RuntimeError(
            f"source image ({source_size} B) does not fit logical partition ({capacity} B)"
        )
    remaining = source_size
    with source.open("rb") as inp:
        for offset, size in extents:
            if not remaining:
                break
            take = min(size, remaining)
            fd.seek(offset)
            while take:
                block = inp.read(min(take, 4 * 1024 * 1024))
                if not block:
                    raise RuntimeError("unexpected EOF while reading source image")
                fd.write(block)
                take -= len(block)
                remaining -= len(block)
    if remaining:
        raise RuntimeError("logical partition ran out of extents during injection")
    return source_size, capacity


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lpunpack", type=Path, required=True)
    parser.add_argument("--super-raw", type=Path, required=True)
    parser.add_argument("--system-image", type=Path, required=True)
    parser.add_argument("--partition", action="append", required=True,
                        help="logical partition to receive the image; repeat for system_a/system_b")
    parser.add_argument("--copy-to", type=Path,
                        help="optional destination copy; omitted means modify --super-raw in place")
    args = parser.parse_args()

    if not args.super_raw.is_file() or not args.system_image.is_file():
        parser.error("--super-raw and --system-image must name regular files")
    if args.copy_to:
        args.copy_to.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.super_raw, args.copy_to)
        super_path = args.copy_to
    else:
        super_path = args.super_raw

    lpmod = load_lpunpack(args.lpunpack)
    metadata = read_metadata(lpmod, super_path)
    source_hash = sha256_file(args.system_image)
    result = []
    with super_path.open("r+b", buffering=0) as fd:
        for name in args.partition:
            extents = extents_for(metadata, name)
            copied, capacity = inject(fd, extents, args.system_image)
            verified = hash_prefix(fd, extents, copied)
            if verified != source_hash:
                raise RuntimeError(f"post-write SHA-256 mismatch for {name}: {verified} != {source_hash}")
            result.append((name, copied, capacity, len(extents), verified))
        fd.flush()
        os.fsync(fd.fileno())
    for name, copied, capacity, extent_count, verified in result:
        print(f"{name}: copied={copied} capacity={capacity} extents={extent_count} sha256={verified}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"logical partition injection failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
